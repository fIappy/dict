#!/usr/bin/env python3
"""Extract the headword list from the COCA 60,000 MDX, one word per line.

The MDX stores 60,000 word+POS rows (rank 1..60000, strictly frequency
descending). Several POS rows share one headword, so the vocabulary is the
53,951 distinct headwords. Order is by total frequency: the sum of every POS
row's frequency for that headword, which is what COCA reports for a word.
Ties fall back to the headword's best (lowest) rank.

Usage:
    python tool/extract_coca_mdx.py "COCA Frequency 60,000 — 2020.mdx" coca-60000.txt

Requires: mdict_utils (pip install mdict-utils)
"""

import argparse
import re
import sys
from collections import defaultdict

from mdict_utils.base.readmdict import MDX

ROW_RE = re.compile(
    r"<div class='pos'>(.*?)</div>"
    r"<div class='rank'>(\d+)</div>"
    r"<div class='freq'>(\d+)</div>"
)
WORD_RE = re.compile(r"<div class='word'>(.*?)</div>")


def extract_rows(path):
    """Yield (headword, rank, freq) for every word+POS row in the MDX."""
    mdx = MDX(path)
    for key, data in mdx.items():
        headword = key.decode("utf-8")
        html = data.decode("utf-8")
        word_div = WORD_RE.search(html)
        if word_div is None:
            raise ValueError(f"entry {headword!r} has no headword div")
        if word_div.group(1) != headword:
            raise ValueError(
                f"entry {headword!r} renders headword {word_div.group(1)!r}"
            )
        rows = ROW_RE.findall(html)
        if not rows:
            raise ValueError(f"entry {headword!r} has no frequency rows")
        for _, rank, freq in rows:
            yield headword, int(rank), int(freq)


def main():
    ap = argparse.ArgumentParser(
        description="Extract the COCA MDX headwords to plain text, most frequent first."
    )
    ap.add_argument("mdx", help="source .mdx file")
    ap.add_argument("out", help="output .txt file, one headword per line")
    args = ap.parse_args()

    total_freq = defaultdict(int)
    best_rank = {}
    rows = 0
    for headword, rank, freq in extract_rows(args.mdx):
        if any(c in "\r\n\t" for c in headword):
            sys.exit(f"headword {headword!r} contains a line break; output would not be one per line")
        total_freq[headword] += freq
        best_rank[headword] = min(rank, best_rank.get(headword, rank))
        rows += 1

    words = sorted(total_freq, key=lambda w: (-total_freq[w], best_rank[w], w))
    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(words))
        fh.write("\n")

    print(f"rows: {rows}")
    print(f"unique headwords: {len(words)}")
    print(f"ranks: {min(best_rank.values())}..{max(best_rank.values())}")
    print(f"wrote: {args.out}")


if __name__ == "__main__":
    main()
