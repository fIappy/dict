"""Parallel worker for the COCA AI learner entries — run inside `eval`.

One call generates a contiguous frequency range and writes validated parts into
content/coca-ai/parts/. Every part is complete on its own, so several agents can
own disjoint ranges at the same time and none of them has to know about the
others.

    %load D:/proj/flutter/dict/tool/ai_defs_kernel.py
    res = await generate_range(start=1000, count=400, per=6, conc=8)
    res = await generate_singles(res["bad"], )

Range units are lines of coca-60000.txt (0-based). `per` is words per model
call, `conc` is simultaneous calls; together they define how hard one agent
pushes.
"""

# pyright: reportUndefinedVariable=false
# `completion` and `wait` are injected by the eval kernel; this module is only
# ever loaded there, never imported by a normal Python process.

import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(r"D:/proj/flutter/dict")
sys.path.insert(0, str(ROOT / "tool"))
import generate_ai_defs as G  # noqa: E402  (needs the tool path first)

OUT = ROOT / "content" / "coca-ai"
PARTS = OUT / "parts"
META = json.loads((OUT / "meta.json").read_text(encoding="utf-8"))
WORDS = [w for w in (ROOT / "coca-60000.txt").read_text(encoding="utf-8").splitlines() if w]


def covered():
    entries = {}
    for path in sorted(PARTS.glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                entry = json.loads(line)
                entries[entry["source_word"]] = entry
    return entries


def save_part(name, entries):
    path = PARTS / f"{name}_{os.getpid()}_{time.time_ns()}.jsonl"
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as fh:
        for entry in entries:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    os.replace(tmp, path)


def parse(text):
    text = text.strip()
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
    data = json.loads(text)
    return data["items"] if isinstance(data, dict) else data


def check_batch(items, text):
    by_word = {}
    for entry in parse(text):
        if isinstance(entry, dict):
            by_word[str(entry.get("word", "")).strip().lower()] = entry
    ok, bad = [], []
    for item in items:
        raw = by_word.get(item["word"].lower())
        if raw is None:
            bad.append((item, "missing from answer"))
            continue
        cleaned, problems = G.check_entry(raw, item)
        if cleaned is None:
            bad.append((item, "; ".join(problems[:4])))
        else:
            ok.append(cleaned)
    return ok, bad


def _call(items, extra=""):
    prompt = G.USER_TEMPLATE.format(n=len(items), word_lines=G.word_lines(items)) + extra
    return completion(prompt, system=G.SYSTEM)


async def generate_range(start, count, per=6, conc=8, tag=None):
    """Generate words[start:start+count]; returns a summary dict."""
    tag = tag or f"g{start:05d}"
    targets = [META[w] for w in WORDS[start:start + count]]
    done = covered()
    todo = [t for t in targets if t["word"] not in done]
    print(f"[{tag}] targets {len(targets)}, already valid {len(targets)-len(todo)}, todo {len(todo)}", flush=True)

    batches = [todo[i:i + per] for i in range(0, len(todo), per)]
    ok_count, bad = 0, []
    t0 = time.time()
    for bstart in range(0, len(batches), conc):
        chunk = batches[bstart:bstart + conc]
        handles = [_call(b) for b in chunk]
        results = wait(handles, raise_errors=False)
        for b, res in zip(chunk, results):
            if isinstance(res, str):
                try:
                    good, bad_items = check_batch(b, res)
                except Exception as exc:
                    good, bad_items = [], [(it, f"parse: {exc}") for it in b]
            else:
                good, bad_items = [], [(it, f"call: {res}") for it in b]
            if good:
                save_part(f"{tag}_{b[0]['rank']:05d}", good)
                ok_count += len(good)
            bad.extend(bad_items)
        print(f"[{tag}] +{ok_count} ok, {len(bad)} bad, {round(time.time()-t0)}s", flush=True)
    return {"tag": tag, "ok": ok_count, "bad": bad, "targets": len(targets)}


async def generate_singles(bad, tag=None, attempts=3, conc=8):
    """Retry failed words one per call; returns the words still failing."""
    tag = tag or "s"
    total = [item for item, _ in bad]
    left = list(total)
    for attempt in range(attempts):
        if not left:
            break
        nxt = []
        for bstart in range(0, len(left), conc):
            chunk = left[bstart:bstart + conc]
            handles = [
                _call([item], "\nHard requirement, checked automatically: the entry for {w} must "
                      "contain the headword '{w}' or a normal inflected form of it at least twice in the passage and at least "
                      "once in every sentence. A sentence that only paraphrases the meaning is rejected. "
                      "The passage must be 95-115 English words.".format(w=item["word"]))
                for item in chunk
            ]
            results = wait(handles, raise_errors=False)
            for item, res in zip(chunk, results):
                good, problems = [], []
                if isinstance(res, str):
                    try:
                        good, problems = check_batch([item], res)
                    except Exception as exc:
                        problems = [(item, f"parse: {exc}")]
                if good:
                    save_part(f"{tag}_{item['rank']:05d}", good)
                else:
                    nxt.append(item)
                    if problems:
                        print(f"[{tag}] {item['word']}: {'; '.join(msg for _, msg in problems[:2])}", flush=True)
        left = nxt
        print(f"[{tag}] attempt {attempt+1}: fixed {len(total)-len(left)}/{len(total)}, left {len(left)}", flush=True)
    return left


def status(limit=2000):
    done = covered()
    have = sum(1 for w in WORDS[:limit] if w in done)
    print(f"coverage first {limit}: {have}/{limit} ({have/limit:.1%})")
    return have
