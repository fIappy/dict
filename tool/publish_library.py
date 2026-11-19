#!/usr/bin/env python3
"""Publish the app's own content into the repository.

Three kinds of data ship as seed files under `assets/seed/`, so a fresh install
on any target — web, Android, Windows — starts with them and an update extends
them without touching what the reader changed:

  assets/seed/custom_home.json   自定义短文 (groups + passages)
  assets/seed/ai_archive.json    AI 生成的主题文章与例句
  assets/seed/favorites.json     收藏的词汇 (groups + words)

Each file carries a `version`, and the app merges a file once, when the build
that carries it changes. Two different rules:

  自定义短文 — this machine *is* the built-in library. The asset is replaced by
  exactly what the app on this machine holds, so an edit, a new passage or a
  deletion all reach the next build. On another machine the merge adds what it
  lacks (its own groups and passages survive untouched) and takes the shipped
  text for an id it already has — the built-in copy wins over a stale one.

  AI 归档 / 收藏 — additive. Entries are matched by id and the local copy of an
  id wins, so nothing the reader wrote is overwritten.

The store this reads is the running app's own:
  * custom_texts.json, custom_groups.json   (自定义短文, see TextLibraryStore)
  * shared_preferences.json                 (AI archive; older custom texts)
  * dict_app.db                             (favorites, SQLite)

Usage:
    python tool/publish_library.py                 # default Windows paths
    python tool/publish_library.py --store <json> --favorites-db <db>
"""

import argparse
import json
import os
import shutil
import sqlite3
import sys
import tempfile

SEED_DIR = os.path.join('assets', 'seed')
CUSTOM = os.path.join(SEED_DIR, 'custom_home.json')
AI = os.path.join(SEED_DIR, 'ai_archive.json')
FAVORITES = os.path.join(SEED_DIR, 'favorites.json')

APP_DATA = os.path.join(os.environ.get('APPDATA', ''), 'com.example', 'local_dict')

# Assets that were left alone because the local copy is behind the committed
# seed. `package_release.sh --publish` turns this into a failed release.
REFUSED = []
DEFAULT_STORE = os.path.join(APP_DATA, 'shared_preferences.json')
DEFAULT_DB = os.path.join(APP_DATA, 'local_dict', 'dict_app.db')


def load_json(path, fallback):
    if not os.path.exists(path):
        return fallback
    try:
        return json.load(open(path, encoding='utf-8'))
    except (OSError, ValueError) as error:
        print(f'{path}: unreadable ({error}), leaving it alone', file=sys.stderr)
        return fallback


def merge_by_id(old, new, key='id'):
    """Old entries first (declaration order), then new ones missing from it,
    with an existing id taking the new copy (the store is the source of truth)."""
    merged = {}
    order = []
    for entry in list(old) + list(new):
        identity = entry.get(key)
        if not identity:
            continue
        if identity not in merged:
            order.append(identity)
        merged[identity] = entry
    return [merged[identity] for identity in order]


def write_library(path, payload, version, changed):
    if changed and os.path.exists(path):
        backup = os.path.join(tempfile.gettempdir(), os.path.basename(path) + '.bak')
        shutil.copy(path, backup)
    payload = {'version': version, **payload}
    json.dump(payload, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    return version


def local_library(store):
    """The passages and groups this machine holds.

    They live in their own files (TextLibraryStore); a store written by an
    older build still has them inside shared_preferences.json, which is read
    as the fallback so publishing keeps working across the move.
    """
    texts_path = os.path.join(APP_DATA, 'custom_texts.json')
    groups_path = os.path.join(APP_DATA, 'custom_groups.json')
    if os.path.exists(texts_path) or os.path.exists(groups_path):
        return (load_json(groups_path, []), load_json(texts_path, []))
    legacy_groups = store.get('flutter.custom_groups')
    legacy_texts = store.get('flutter.custom_texts')
    return (json.loads(legacy_groups) if legacy_groups else [],
            json.loads(legacy_texts) if legacy_texts else [])


def merged_seed_version(store, key='flutter.custom_library_version'):
    """The seed version the app on this machine has already merged.

    `None` when the store predates that bookkeeping (or is not there at all):
    then there is nothing to compare against.
    """
    value = store.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return int(value)


def publish_custom(store, dry_run, force):
    """Replaces the asset with this machine's library.

    Not a union: this machine is the built-in library, so a passage deleted
    here must be gone from the next build too. An empty library is refused —
    that is a wrong path or a fresh profile, not a decision.
    """
    data = load_json(CUSTOM, {'version': 1, 'groups': [], 'texts': []})
    groups, texts = local_library(store)
    seed_version = int(data.get('version', 1))
    merged = merged_seed_version(store)
    if merged is not None and merged < seed_version and not force:
        REFUSED.append(os.path.basename(CUSTOM))
        print(f'{CUSTOM}: refusing to publish — this machine last merged seed '
              f'v{merged}, while the committed seed is v{seed_version}. '
              f'Run the app here once so the newer built-in text lands in the '
              f'local library, then publish again (or pass --force).',
              file=sys.stderr)
        return (len(data.get('groups', [])), len(data.get('texts', [])),
                seed_version, False)
    if not texts and not force:
        print(f'{CUSTOM}: this machine has no passages, leaving the asset alone '
              f'(use --force to publish an empty library)', file=sys.stderr)
        return (len(data.get('groups', [])), len(data.get('texts', [])),
                int(data.get('version', 1)), False)
    changed = (groups != data.get('groups', []) or texts != data.get('texts', []))
    version = int(data.get('version', 1)) + (1 if changed else 0)
    if not dry_run and changed:
        write_library(CUSTOM, {'groups': groups, 'texts': texts}, version, changed)
    return len(groups), len(texts), version, changed


def publish_ai(store, dry_run):
    data = load_json(AI, {'version': 1, 'items': []})
    items = json.loads(store.get('flutter.ai_archive_v1', '[]'))
    merged = merge_by_id(data.get('items', []), items)
    changed = merged != data.get('items', [])
    version = int(data.get('version', 1)) + (1 if changed else 0)
    if not dry_run:
        write_library(AI, {'items': merged}, version, changed)
    return len(merged), version, changed


def publish_favorites(db_path, dry_run, force, store):
    data = load_json(FAVORITES, {'version': 1, 'groups': [], 'items': []})
    seed_version = int(data.get('version', 1))
    merged = merged_seed_version(store, 'flutter.favorites_seed_version')
    if merged is not None and merged < seed_version and not force:
        REFUSED.append(os.path.basename(FAVORITES))
        print(f'{FAVORITES}: refusing to publish — this machine last merged seed '
              f'v{merged}, while the committed seed is v{seed_version}. '
              f'Run the app here once so the built-in words land in the local '
              f'database, then publish again (or pass --force).', file=sys.stderr)
        return (len(data.get('groups', [])), len(data.get('items', [])),
                seed_version, False)
    if not os.path.exists(db_path):
        return 0, 0, int(data.get('version', 1)), False
    db = sqlite3.connect(db_path)
    db.row_factory = sqlite3.Row
    groups = [dict(row) for row in db.execute(
        'select id, name, description, color, icon, sort_order, created_at '
        'from favorite_groups order by sort_order, created_at')]
    items = [dict(row) for row in db.execute(
        'select id, word, group_id, phonetic, definition_snippet, '
        'examples_snippet, note, dict_source, tags, created_at, updated_at '
        'from favorites order by created_at')]
    db.close()
    merged_groups = merge_by_id(data.get('groups', []), groups)
    merged_items = merge_by_id(data.get('items', []), items)
    changed = (merged_groups != data.get('groups', [])
               or merged_items != data.get('items', []))
    version = int(data.get('version', 1)) + (1 if changed else 0)
    if not dry_run:
        write_library(FAVORITES, {'groups': merged_groups, 'items': merged_items},
                      version, changed)
    return len(merged_groups), len(merged_items), version, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--store', default=DEFAULT_STORE)
    parser.add_argument('--favorites-db', default=DEFAULT_DB)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--force', action='store_true',
                        help='publish the custom library even when it is empty')
    args = parser.parse_args()

    if os.path.exists(args.store):
        store = json.load(open(args.store, encoding='utf-8'))
    else:
        # The custom library keeps its own files since TextLibraryStore; a
        # machine without shared_preferences.json can still publish it.
        if not (os.path.exists(os.path.join(APP_DATA, 'custom_texts.json'))
                or os.path.exists(os.path.join(APP_DATA, 'custom_groups.json'))):
            sys.exit(f'store not found: {args.store}')
        print(f'{args.store}: missing, publishing from the custom library files',
              file=sys.stderr)
        store = {}

    groups, texts, version, changed = publish_custom(
        store, args.dry_run, args.force)
    print(f'{CUSTOM}: {groups} groups, {texts} texts, version {version}'
          f'{" (updated)" if changed else " (unchanged)"}')

    items, version, changed = publish_ai(store, args.dry_run)
    print(f'{AI}: {items} items, version {version}'
          f'{" (updated)" if changed else " (unchanged)"}')

    groups, items, version, changed = publish_favorites(
        args.favorites_db, args.dry_run, args.force, store)
    print(f'{FAVORITES}: {groups} groups, {items} words, version {version}'
          f'{" (updated)" if changed else " (unchanged)"}')

    # A refusal has to fail the build that asked for the publish, otherwise
    # `package_release.sh --publish` ships a library it silently did not update.
    if REFUSED and not args.dry_run:
        sys.exit('publish refused for: ' + ', '.join(REFUSED))


if __name__ == '__main__':
    main()
