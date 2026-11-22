#!/usr/bin/env python3
"""Pack content/coca-ai/words.jsonl into a standard MDict dictionary.

Produces two files that dictionary software loads together:

  COCA 60k AI.mdx   - 53,951 entries, HTML definitions, UTF-8
  COCA 60k AI.mdd   - coca-ai.css referenced by every entry

The .mdx text format is one headword line, the HTML definition, then a line
containing only `</>` as the record separator. Display rules live in the CSS
resource so each entry stays small.

    python tool/build_coca_mdx.py --limit 100 --out content/coca-ai/mdx/test
    python tool/build_coca_mdx.py
"""

import argparse
import html
import shutil
from pathlib import Path

from mdict_utils.writer import pack, pack_mdd_file, pack_mdx_txt

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "content" / "coca-ai"
CSS_NAME = "coca-ai.css"

CSS = """\
:root { color-scheme: light dark; }
body { margin: 0; }
.coca { font-family: -apple-system, "Segoe UI", "Noto Sans SC", sans-serif;
  line-height: 1.6; padding: 10px 12px 14px; max-width: 46em; }
.hw { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap;
  border-bottom: 2px solid currentColor; padding-bottom: 6px; margin-bottom: 10px; }
.hw .w { font-size: 26px; font-weight: 700; letter-spacing: .2px; }
.hw .rank { font-size: 12px; opacity: .65; }
.pos { display: inline-block; font-size: 12px; padding: 1px 7px; margin: 0 6px 8px 0;
  border: 1px solid currentColor; border-radius: 10px; opacity: .8; }
.sec { margin: 10px 0; }
.lbl { font-size: 11px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase;
  opacity: .55; margin-bottom: 3px; }
p { margin: 4px 0; }
.colloc { margin: 6px 0 10px; }
.colloc span { display: inline-block; font-size: 12.5px; padding: 2px 8px; margin: 0 5px 5px 0;
  background: rgba(127,127,127,.16); border-radius: 4px; }
.ex { margin: 8px 0 10px; padding-left: 10px; border-left: 3px solid rgba(127,127,127,.35); }
.ex .en { font-weight: 500; }
.ex .zh { opacity: .72; font-size: 13px; }
.psg-title { font-weight: 600; margin-bottom: 2px; }
.psg { font-size: 13.5px; }
.foot { margin-top: 14px; padding-top: 6px; border-top: 1px solid rgba(127,127,127,.3);
  font-size: 11px; opacity: .5; }
"""


def esc(text):
    return html.escape(str(text), quote=False)


def render(entry):
    parts = [
        f"<link rel='stylesheet' href='{CSS_NAME}'>",
        "<div class='coca'>",
        "<div class='hw'><span class='w'>" + esc(entry["word"]) + "</span>"
        "<span class='rank'>COCA " + esc(entry["rank"]) + " · " + esc(entry["freq"]) + "</span></div>",
    ]
    for pos in entry.get("pos") or []:
        parts.append("<span class='pos'>" + esc(pos) + "</span>")
    parts.append("<div class='sec'><div class='lbl'>释义</div><p>" + esc(entry["meaning_zh"]) + "</p></div>")
    parts.append("<div class='sec'><div class='lbl'>用法</div><p>" + esc(entry["usage_zh"]) + "</p></div>")
    if entry.get("collocations"):
        parts.append("<div class='colloc'>" + "".join("<span>" + esc(c) + "</span>" for c in entry["collocations"]) + "</div>")
    if entry.get("sentences"):
        parts.append("<div class='sec'><div class='lbl'>例句</div>")
        for sentence in entry["sentences"]:
            parts.append("<div class='ex'><p class='en'>" + esc(sentence["text"]) + "</p>")
            parts.append("<p class='zh'>" + esc(sentence.get("translation", "")) + "</p></div>")
        parts.append("</div>")
    passage = entry.get("passage") or {}
    if passage.get("text"):
        parts.append("<div class='sec'><div class='lbl'>短文</div>")
        if passage.get("title"):
            parts.append("<p class='psg-title'>" + esc(passage["title"]) + "</p>")
        parts.append("<p class='psg'>" + esc(passage["text"]) + "</p></div>")
    parts.append("<div class='foot'>AI 释义 · " + esc(entry.get("model", "")) + " · " + esc(entry.get("generated_at", "")) + " · 仅供学习</div>")
    parts.append("</div>")
    return "".join(parts)


def main():
    ap = argparse.ArgumentParser(description="Build an MDict (.mdx + .mdd) from words.jsonl")
    ap.add_argument("--input", default=str(OUT_DIR / "words.jsonl"))
    ap.add_argument("--out", default=str(OUT_DIR / "mdx" / "COCA 60k AI"))
    ap.add_argument("--limit", type=int, default=0, help="only the first N entries (testing)")
    ap.add_argument("--title", default="COCA 60000 AI 释义")
    ap.add_argument("--description", default="COCA 2020 60k 词表 AI 释义：中文用法、搭配、例句与短文。")
    args = ap.parse_args()

    out_base = Path(args.out)
    out_base.parent.mkdir(parents=True, exist_ok=True)
    work = out_base.parent / "build"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    css_dir = work / "resources"
    css_dir.mkdir()
    (css_dir / CSS_NAME).write_text(CSS, encoding="utf-8")

    txt_path = work / "source.txt"
    count = 0
    with open(args.input, encoding="utf-8") as src, txt_path.open("w", encoding="utf-8", newline="\n") as out:
        for line in src:
            if not line.strip():
                continue
            import json
            entry = json.loads(line)
            out.write(entry["word"] + "\n")
            out.write(render(entry) + "\n")
            out.write("</>\n")
            count += 1
            if args.limit and count >= args.limit:
                break

    print(f"entries: {count}")
    print(f"source txt: {txt_path} ({txt_path.stat().st_size/1e6:.1f} MB)")

    records = pack_mdx_txt(str(txt_path), encoding="UTF-8")
    mdx_path = Path(str(out_base) + ".mdx")
    with mdx_path.open("wb") as fh:
        pack(str(mdx_path), records, args.title, args.description, encoding="UTF-8")

    mdd_records = pack_mdd_file(str(css_dir))
    mdd_path = Path(str(out_base) + ".mdd")
    with mdd_path.open("wb") as fh:
        pack(str(mdd_path), mdd_records, args.title, args.description, is_mdd=True)

    print(f"wrote: {mdx_path} ({mdx_path.stat().st_size/1e6:.1f} MB)")
    print(f"wrote: {mdd_path} ({mdd_path.stat().st_size/1e3:.1f} KB)")
    if count < 1000:
        print("(test build)")


if __name__ == "__main__":
    main()
