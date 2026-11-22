#!/usr/bin/env python3
"""Assemble the AI learner entries into content/coca-ai/words.jsonl.

`tool/generate_ai_defs.py` and the harness both drop validated entries into
content/coca-ai/parts/*.jsonl. This script picks one entry per headword (the
last file wins, so corrections named `zz*` override earlier attempts), orders
them by coca-60000.txt, and writes the shipped file.

    python tool/assemble_ai_defs.py --limit 1000

Checks that every target word is covered, every entry passes the same
validation used during generation, and the frequency order is strict. Missing
words are listed and make the command fail, so a half-finished folder never
looks complete.
"""

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

from generate_ai_defs import EN_WORD, check_entry

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "content" / "coca-ai"
PARTS = OUT_DIR / "parts"
WORDS_TXT = ROOT / "coca-60000.txt"


ABBREV = re.compile(r"(?:a\.m\.|p\.m\.|e\.g\.|i\.e\.|vs\.|etc\.)$", re.I)


def cap_sentences(text):
    """Capitalize sentence starts the model left lowercase.

    A lowercase word after a closing quote is a speech attribution
    (`"Are you coming?" he asked`) and stays as written.
    """
    for m in reversed(list(re.finditer(r"([.!?])\s+([a-z])", text))):
        if text[:m.start(1) + 1].endswith(('"', "'")):
            continue
        token = text[:m.start(1)].rsplit(" ", 1)[-1] + "."
        if ABBREV.search(token):
            continue
        start = m.start(2)
        text = text[:start] + text[start].upper() + text[start + 1:]
    return text


def cap_first(text):
    """Sentence-case a model string without touching quotes or digits."""
    for i, ch in enumerate(text):
        if ch.isalpha():
            return text[:i] + ch.upper() + text[i + 1:]
        if not (ch.isdigit() or ch in '"\''):
            break
    return text


def load_parts(meta):
    entries = {}
    rejected = []
    for path in sorted(PARTS.glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            entry = json.loads(line)
            expected = meta.get(entry.get("source_word", ""))
            if expected is None:
                rejected.append((path.name, entry.get("source_word"), "not in meta"))
                continue
            cleaned, problems = check_entry(entry, expected)
            if cleaned is None:
                rejected.append((path.name, entry.get("source_word"), "; ".join(problems[:3])))
            else:
                entries[entry["source_word"]] = cleaned
    return entries, rejected


def main():
    ap = argparse.ArgumentParser(description="Assemble AI learner entries for COCA headwords.")
    ap.add_argument("--limit", type=int, default=1000)
    ap.add_argument("--start", type=int, default=0)
    args = ap.parse_args()

    meta = json.loads((OUT_DIR / "meta.json").read_text(encoding="utf-8"))
    words = [w for w in WORDS_TXT.read_text(encoding="utf-8").splitlines() if w]
    targets = words[args.start:args.start + args.limit]

    entries, rejected = load_parts(meta)
    missing = [w for w in targets if w not in entries]
    ordered = [entries[w] for w in targets if w in entries]

    for path, word, why in rejected:
        print(f"rejected {path}: {word}: {why}", file=sys.stderr)

    if missing:
        print(f"missing ({len(missing)}): {missing[:20]}", file=sys.stderr)
        sys.exit(f"refusing to write a partial file: {len(ordered)}/{len(targets)} entries")

    today = datetime.date.today().isoformat()
    out = []
    for position, entry in enumerate(ordered, 1):
        entry = dict(entry)
        entry["rank"] = position
        entry["sentences"] = [
            {**s, "text": cap_first(s["text"].strip())} for s in entry["sentences"]
        ]
        entry["passage"] = {
            **entry["passage"],
            "title": cap_first(entry["passage"]["title"].strip()),
            "text": cap_sentences(cap_first(entry["passage"]["text"].strip())),
        }
        entry["schema"] = 1
        entry["model"] = "deepseek-flash"
        entry["generated_at"] = today
        out.append(entry)

    path = OUT_DIR / "words.jsonl"
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for entry in out:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")

    descending = all(a["freq"] >= b["freq"] for a, b in zip(out, out[1:]))
    print(f"entries: {len(out)}/{len(targets)}")
    print(f"freq descending: {descending}")
    print(f"passage words: {min(len(EN_WORD.findall(e['passage']['text'])) for e in out)}"
          f"..{max(len(EN_WORD.findall(e['passage']['text'])) for e in out)}")
    print(f"rejected part entries: {len(rejected)}")
    print(f"wrote: {path}")


if __name__ == "__main__":
    main()
