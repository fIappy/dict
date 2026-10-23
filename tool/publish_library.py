#!/usr/bin/env python3
"""Publish the app's own content into the repository.

Three kinds of data ship as seed files under `assets/seed/`, so a fresh install
on any target — web, Android, Windows — starts with them and an update extends
them without touching what the reader changed:

  assets/seed/custom_home.json   自定义短文 (groups + passages)
  assets/seed/ai_archive.json    AI 生成的主题文章与例句
  assets/seed/favorites.json     收藏的词汇 (groups + words)

Each file carries a `version`. The app merges a file when its version is newer
than the one already merged: entries whose id is missing are added, and an id
that already exists keeps the local copy (that is the reader's edit). Bumping
the version is what makes an installed app pick new content up.

The store this reads is the running app's own:
  * shared_preferences.json  (custom texts, AI archive)
  * dict_app.db              (favorites, SQLite)

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


def publish_custom(store, dry_run):
    data = load_json(CUSTOM, {'version': 1, 'groups': [], 'texts': []})
    groups = json.loads(store.get('flutter.custom_groups', '[]'))
    texts = json.loads(store.get('flutter.custom_texts', '[]'))
    merged_groups = merge_by_id(data.get('groups', []), groups)
    merged_texts = merge_by_id(data.get('texts', []), texts)
    changed = (merged_groups != data.get('groups', [])
               or merged_texts != data.get('texts', []))
    version = int(data.get('version', 1)) + (1 if changed else 0)
    if not dry_run:
        write_library(CUSTOM, {'groups': merged_groups, 'texts': merged_texts}, version, changed)
    return len(merged_groups), len(merged_texts), version, changed


def publish_ai(store, dry_run):
    data = load_json(AI, {'version': 1, 'items': []})
    items = json.loads(store.get('flutter.ai_archive_v1', '[]'))
    merged = merge_by_id(data.get('items', []), items)
    changed = merged != data.get('items', [])
    version = int(data.get('version', 1)) + (1 if changed else 0)
    if not dry_run:
        write_library(AI, {'items': merged}, version, changed)
    return len(merged), version, changed


def publish_favorites(db_path, dry_run):
    data = load_json(FAVORITES, {'version': 1, 'groups': [], 'items': []})
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
    args = parser.parse_args()

    if not os.path.exists(args.store):
        sys.exit(f'store not found: {args.store}')
    store = json.load(open(args.store, encoding='utf-8'))

    groups, texts, version, changed = publish_custom(store, args.dry_run)
    print(f'{CUSTOM}: {groups} groups, {texts} texts, version {version}'
          f'{" (updated)" if changed else " (unchanged)"}')

    items, version, changed = publish_ai(store, args.dry_run)
    print(f'{AI}: {items} items, version {version}'
          f'{" (updated)" if changed else " (unchanged)"}')

    groups, items, version, changed = publish_favorites(args.favorites_db, args.dry_run)
    print(f'{FAVORITES}: {groups} groups, {items} words, version {version}'
          f'{" (updated)" if changed else " (unchanged)"}')


if __name__ == '__main__':
    main()
