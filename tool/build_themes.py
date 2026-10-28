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

The third column of each row is the word's Chinese gloss; it travels with the
group as `glosses` (word -> 释义) because the 背词 window shows the two side by
side and a parallel list would fall out of step with any filtered view.

A gloss ending in `*`, `**` or `***` marks the word as one to drill harder: the
stars are counted, stripped from the text, and written to
`assets/seed/vocab_stars.json`, which the 背词 window merges once per version.
"""

import argparse
import glob
import json
import os
import re

SRC = os.path.join('tool', 'coca_theme')
OUT = os.path.join('assets', 'data', 'themes.json')
STARS_OUT = os.path.join('assets', 'seed', 'vocab_stars.json')
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
    """Returns (number, name, hint, words, glosses) for one theme file."""
    match = FILE.match(os.path.basename(path))
    if not match:
        raise SystemExit(f'{path}: not a NN_<名称>.txt file')
    number, name = match.group('number'), match.group('name')
    words = []
    glosses = {}
    star_counts = {}
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
        gloss = (row.group('gloss') or '').strip()
        # `*` / `**` / `***` after the meaning is the star rating, not text.
        stars = 0
        while gloss.endswith('*'):
            stars += 1
            gloss = gloss[:-1].rstrip()
        if stars:
            star_counts[word] = stars
        if gloss:
            glosses[word] = gloss
    if not words:
        raise SystemExit(f'{path}: no words')
    return number, name, HINTS.get(number, ''), words, glosses, star_counts


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
    star_seed = {}
    for path in paths:
        number, name, hint, words, glosses, stars = parse_file(path)
        star_seed.update(stars)
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
            'groups': [
                {'id': 'all', 'label': name, 'words': words, 'glosses': glosses}
            ],
        })

    return {
        'version': 2,
        'source': f'COCA 20000 · {len(scenes)} 个主题 · {len(placed)} 词',
        'scenes': scenes,
    }, star_seed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--src', default=SRC)
    parser.add_argument('--out', default=OUT)
    args = parser.parse_args()

    data, stars = build(args.src)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as handle:
        json.dump(data, handle, ensure_ascii=False, separators=(',', ':'))

    # The star seed bumps its version only when the ratings changed, so the app
    # merges it once and later reader changes to a star survive.
    version = 1
    if os.path.exists(STARS_OUT):
        try:
            with open(STARS_OUT, encoding='utf-8') as handle:
                old = json.load(handle)
            version = int(old.get('version', 1))
            if old.get('stars') == stars:
                version -= 1  # unchanged: keep the version we had
        except (OSError, ValueError):
            pass
    version += 1
    os.makedirs(os.path.dirname(STARS_OUT), exist_ok=True)
    with open(STARS_OUT, 'w', encoding='utf-8') as handle:
        json.dump({'version': version, 'stars': stars}, handle,
                  ensure_ascii=False, indent=0, sort_keys=True)

    total = sum(scene['count'] for scene in data['scenes'])
    size = os.path.getsize(args.out) / 1024
    print(f'{args.out}: {len(data["scenes"])} scenes, {total} words, '
          f'{size:.0f} KB')
    print(f'{STARS_OUT}: {len(stars)} starred words, version {version}')


if __name__ == '__main__':
    main()
