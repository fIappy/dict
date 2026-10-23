#!/usr/bin/env python3
"""Publish the app's own 自定义短文 library into the repository.

The app keeps custom texts in `shared_preferences`; `assets/seed/custom_home.json`
is the copy that ships with the build, so a fresh install starts with it and an
update can extend it. This script merges the live store into that file:

  * every group and entry from the store is added or updated in the library
    (the store is the source of truth — what you edited locally is what ships);
  * entries that only exist in the library are kept as they are;
  * the file's `version` is bumped, which is what makes an installed app pick
    the new entries up (see `CustomTextProvider.ensureSeeded`).

Idempotent: running it twice writes the same content and does not bump twice
when nothing changed.

Usage:
    python tool/publish_custom_library.py                 # default Windows store
    python tool/publish_custom_library.py --store <path>  # another machine
"""

import argparse
import json
import os
import shutil
import sys

LIBRARY = os.path.join('assets', 'seed', 'custom_home.json')
DEFAULT_STORE = os.path.join(
    os.environ.get('APPDATA', ''),
    'com.example',
    'local_dict',
    'shared_preferences.json',
)


def load_store(path):
    raw = json.load(open(path, encoding='utf-8'))
    texts = json.loads(raw.get('flutter.custom_texts', '[]'))
    groups = json.loads(raw.get('flutter.custom_groups', '[]'))
    return groups, texts


def merge(library_groups, library_texts, store_groups, store_texts):
    groups = {g['id']: g for g in library_groups if g.get('id')}
    for group in store_groups:
        if group.get('id'):
            groups[group['id']] = group

    texts = {t['id']: t for t in library_texts if t.get('id')}
    for item in store_texts:
        if item.get('id'):
            texts[item['id']] = item

    # Stable, deterministic order: groups as declared, entries by creation time.
    ordered_groups = [groups[g] for g in dict.fromkeys([g.get('id') for g in library_groups] + [g['id'] for g in store_groups]) if g]
    ordered_texts = sorted(texts.values(), key=lambda t: (t.get('createdAt', ''), t['id']))
    return ordered_groups, ordered_texts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--store', default=DEFAULT_STORE)
    args = parser.parse_args()

    if not os.path.exists(args.store):
        sys.exit(f'store not found: {args.store}')
    if not os.path.exists(LIBRARY):
        sys.exit(f'library not found: {LIBRARY} (run from the repository root)')

    library = json.load(open(LIBRARY, encoding='utf-8'))
    store_groups, store_texts = load_store(args.store)
    groups, texts = merge(
        library.get('groups', []),
        library.get('texts', []),
        store_groups,
        store_texts,
    )

    changed = (
        groups != library.get('groups', [])
        or texts != library.get('texts', [])
    )
    version = int(library.get('version', 1)) + (1 if changed else 0)
    if changed:
        shutil.copy(LIBRARY, LIBRARY + '.bak')
    json.dump(
        {'version': version, 'groups': groups, 'texts': texts},
        open(LIBRARY, 'w', encoding='utf-8'),
        ensure_ascii=False,
        indent=1,
    )
    print(
        f'{LIBRARY}: version {version}, {len(groups)} groups, {len(texts)} texts '
        f'({"updated" if changed else "unchanged"})'
    )


if __name__ == '__main__':
    main()
