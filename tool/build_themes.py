#!/usr/bin/env python3
"""Build assets/data/themes.json from the curated COCA theme files.

Source: tool/coca_theme/NN_<名称>.txt, one file per theme, in COCA order:

    == 通用（功能词与常用副词）（786 词）==
    1	the	（定冠词）这/那
    2	be	是

The rank column is the word's place in coca-20000.txt; the files partition the
vocabulary (no word sits in two themes), so the scene counts add up to the
number of curated words.

Each theme becomes one scene with a single group. The app's ThemeScene model
still carries groups because the JSON contract predates this flat taxonomy, and
a single group is what a flat list is.
"""

import argparse
import glob
import json
import os
import re

SRC = os.path.join('tool', 'coca_theme')
OUT = os.path.join('assets', 'data', 'themes.json')
COCA = 'coca-20000.txt'

HEADER = re.compile(r'^==\s*(?P<label>.+?)（(?P<count>\d+)\s*词）==$')
ROW = re.compile(r'^(?P<rank>\d+)\t(?P<word>[^\t]+)(?:\t(?P<gloss>.*))?$')
FILE = re.compile(r'^(?P<number>\d{2})_(?P<name>.+)\.txt$')

# The index file explains what the three general themes hold; the rest are
# self-describing.
HINTS = {
    '01': '功能词与常用副词',
    '02': '一般性质与状态形容词与分词',
    '39': '抽象概念与一般名词',
}


def parse_file(path):
    """Returns (number, name, hint, words) for one theme file."""
    match = FILE.match(os.path.basename(path))
    if not match:
        raise SystemExit(f'{path}: not a NN_<名称>.txt file')
    number, name = match.group('number'), match.group('name')
    words = []
    seen = set()
    for line in open(path, encoding='utf-8-sig'):
        line = line.strip().lstrip('\ufeff')
        if not line or line.startswith('=='):
            continue
        row = ROW.match(line)
        if not row:
            raise SystemExit(f'{path}: unreadable row: {line!r}')
        word = row.group('word').strip().lower()
        if word in seen:
            continue
        seen.add(word)
        words.append(word)
    if not words:
        raise SystemExit(f'{path}: no words')
    return number, name, HINTS.get(number, ''), words


def normalize(word):
    """COCA's file writes a few contractions with a doubled apostrophe
    (`n''t`, `o''clock`); the theme files spell them properly."""
    return word.replace("''", "'")


def coca_ranks():
    ranks = {}
    for index, line in enumerate(open(COCA, encoding='utf-8')):
        word = normalize(line.strip().lower())
        if word and word not in ranks:
            ranks[word] = index + 1
    return ranks


def build(src):
    paths = [path for path in sorted(glob.glob(os.path.join(src, '[0-9][0-9]_*.txt')))
             if not os.path.basename(path).startswith('00_')]  # 00_索引 lists the set
    if not paths:
        raise SystemExit(f'{src}: no theme files')
    ranks = coca_ranks()

    scenes = []
    placed = set()
    for path in paths:
        number, name, hint, words = parse_file(path)
        unknown = [w for w in words if w not in ranks]
        if unknown:
            raise SystemExit(f'{path}: not in {COCA}: {unknown[:5]}')
        # The files are meant to be in frequency order; a reshuffled file would
        # silently change what the first page shows.
        order = [ranks[w] for w in words]
        if order != sorted(order):
            raise SystemExit(f'{path}: words are not in COCA order')
        overlap = placed.intersection(words)
        if overlap:
            raise SystemExit(f'{path}: already placed elsewhere: {sorted(overlap)[:5]}')
        placed.update(words)
        scenes.append({
            'id': f't{number}',
            'label': name,
            'hint': hint,
            'count': len(words),
            'groups': [{'id': 'all', 'label': name, 'words': words}],
        })

    return {
        'version': 2,
        'source': f'COCA 20000 · {len(scenes)} 个主题 · {len(placed)} 词',
        'scenes': scenes,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--src', default=SRC)
    parser.add_argument('--out', default=OUT)
    args = parser.parse_args()

    data = build(args.src)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as handle:
        json.dump(data, handle, ensure_ascii=False, separators=(',', ':'))

    total = sum(scene['count'] for scene in data['scenes'])
    size = os.path.getsize(args.out) / 1024
    print(f'{args.out}: {len(data["scenes"])} scenes, {total} words, '
          f'{size:.0f} KB')


if __name__ == '__main__':
    main()
