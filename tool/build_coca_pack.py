#!/usr/bin/env python3
"""Build normalized SQLite and zstd-compressed learning packs from words_cleaned.jsonl."""

import argparse
import datetime
import hashlib
import json
import sqlite3
from pathlib import Path

import zstandard as zstd

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = ROOT / "content" / "coca-ai" / "words_cleaned.jsonl"
DEFAULT_OUT_DIR = ROOT / "content" / "coca-ai" / "pack"
RAW_JSONL = ROOT / "content" / "coca-ai" / "words.jsonl"
RAW_MDX = ROOT / "content" / "coca-ai" / "mdx" / "COCA 60k AI.mdx"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while chunk := fh.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def compress_zst(src: Path, dst: Path, level: int) -> None:
    cctx = zstd.ZstdCompressor(level=level)
    with src.open("rb") as fin, dst.open("wb") as fout:
        cctx.copy_stream(fin, fout)


def verify_zst_roundtrip(zst_path: Path, expected_sha256: str) -> None:
    dctx = zstd.ZstdDecompressor()
    h = hashlib.sha256()
    with zst_path.open("rb") as fin, dctx.stream_reader(fin) as reader:
        while chunk := reader.read(1024 * 1024):
            h.update(chunk)
    actual = h.hexdigest()
    if actual != expected_sha256:
        raise RuntimeError(
            f"zstd roundtrip mismatch for {zst_path}: expected {expected_sha256}, got {actual}"
        )


def to_slim_json(entry: dict) -> str:
    payload = {
        "r": entry["rank"],
        "cr": entry["coca_rank"],
        "w": entry["word"],
        "f": entry["freq"],
        "p": entry["pos"],
        "tid": entry["theme_id"],
        "tg": entry["theme_gloss"],
        "reg": entry["register"],
        "m": entry["meaning_zh"],
        "u": entry["usage_zh"],
        "c": entry["collocations"],
        "pat": entry["patterns"],
        "exp": entry["expressions"],
        "s": [[s["text"], s["translation"], s["phrases"]] for s in entry["sentences"]],
        "g": [
            entry["passage"]["title"],
            entry["passage"]["text"],
            entry["passage"]["phrases"],
        ],
    }
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def build_sqlite(entries: list[dict], db_path: Path, built_at: str) -> dict:
    if db_path.exists():
        db_path.unlink()

    con = sqlite3.connect(db_path)
    try:
        con.execute("PRAGMA page_size = 4096")
        con.execute("PRAGMA journal_mode = OFF")
        con.execute("PRAGMA synchronous = OFF")

        con.executescript(
            """
            CREATE TABLE meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE lexemes (
              rank INTEGER PRIMARY KEY,
              coca_rank INTEGER NOT NULL,
              word TEXT NOT NULL UNIQUE,
              freq INTEGER NOT NULL,
              pos TEXT NOT NULL,
              theme_id TEXT,
              theme_gloss TEXT,
              register TEXT NOT NULL,
              meaning_zh TEXT NOT NULL,
              usage_zh TEXT NOT NULL
            );
            CREATE TABLE chunks (
              id INTEGER PRIMARY KEY,
              word_rank INTEGER NOT NULL,
              kind TEXT NOT NULL CHECK(kind IN ('collocation', 'pattern', 'expression')),
              text TEXT NOT NULL
            );
            CREATE TABLE sentences (
              id INTEGER PRIMARY KEY,
              word_rank INTEGER NOT NULL,
              seq INTEGER NOT NULL,
              text TEXT NOT NULL,
              translation TEXT NOT NULL,
              phrases_json TEXT NOT NULL
            );
            CREATE TABLE passages (
              word_rank INTEGER PRIMARY KEY,
              title TEXT NOT NULL,
              text TEXT NOT NULL,
              phrases_json TEXT NOT NULL
            );
            """
        )

        lex_rows = []
        chunk_rows = []
        sent_rows = []
        psg_rows = []
        colloc_count = pattern_count = expr_count = theme_linked = 0
        cid = sid = 1

        for e in entries:
            r = e["rank"]
            if e.get("theme_id") is not None:
                theme_linked += 1
            lex_rows.append(
                (
                    r,
                    e["coca_rank"],
                    e["word"],
                    e["freq"],
                    ",".join(e["pos"]),
                    e.get("theme_id"),
                    e.get("theme_gloss"),
                    e["register"],
                    e["meaning_zh"],
                    e["usage_zh"],
                )
            )
            for item in e.get("collocations", []):
                chunk_rows.append((cid, r, "collocation", item))
                cid += 1
                colloc_count += 1
            for item in e.get("patterns", []):
                chunk_rows.append((cid, r, "pattern", item))
                cid += 1
                pattern_count += 1
            for item in e.get("expressions", []):
                chunk_rows.append((cid, r, "expression", item))
                cid += 1
                expr_count += 1
            for seq, s in enumerate(e.get("sentences", [])):
                sent_rows.append(
                    (
                        sid,
                        r,
                        seq,
                        s["text"],
                        s["translation"],
                        json.dumps(s["phrases"], ensure_ascii=False, separators=(",", ":")),
                    )
                )
                sid += 1
            psg = e["passage"]
            psg_rows.append(
                (
                    r,
                    psg["title"],
                    psg["text"],
                    json.dumps(psg["phrases"], ensure_ascii=False, separators=(",", ":")),
                )
            )

        con.executemany(
            "INSERT INTO lexemes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", lex_rows
        )
        con.executemany("INSERT INTO chunks VALUES (?, ?, ?, ?)", chunk_rows)
        con.executemany(
            "INSERT INTO sentences VALUES (?, ?, ?, ?, ?, ?)", sent_rows
        )
        con.executemany("INSERT INTO passages VALUES (?, ?, ?, ?)", psg_rows)

        stats = {
            "schema_version": "2",
            "built_at": built_at,
            "entry_count": str(len(lex_rows)),
            "chunk_count": str(len(chunk_rows)),
            "collocation_count": str(colloc_count),
            "pattern_count": str(pattern_count),
            "expression_count": str(expr_count),
            "sentence_count": str(len(sent_rows)),
            "theme_linked_count": str(theme_linked),
            "source": "COCA 2020 60k AI (cleaned)",
        }
        con.executemany("INSERT INTO meta VALUES (?, ?)", list(stats.items()))

        con.executescript(
            """
            CREATE INDEX idx_lexemes_coca_rank ON lexemes(coca_rank);
            CREATE INDEX idx_lexemes_theme ON lexemes(theme_id) WHERE theme_id IS NOT NULL;
            CREATE INDEX idx_lexemes_register ON lexemes(register) WHERE register != 'standard';
            CREATE INDEX idx_chunks_word ON chunks(word_rank);
            CREATE INDEX idx_chunks_kind_text ON chunks(kind, text);
            CREATE INDEX idx_sentences_word ON sentences(word_rank);
            ANALYZE;
            VACUUM;
            """
        )

        check = con.execute("PRAGMA integrity_check").fetchone()[0]
        if check != "ok":
            raise RuntimeError(f"SQLite integrity_check failed for {db_path}: {check}")
        con.commit()
    finally:
        con.close()

    return {
        "entries": len(lex_rows),
        "chunks": len(chunk_rows),
        "collocations": colloc_count,
        "patterns": pattern_count,
        "expressions": expr_count,
        "sentences": len(sent_rows),
        "theme_linked": theme_linked,
    }


def write_slim_jsonl_zst(entries: list[dict], out_path: Path, level: int) -> dict:
    cctx = zstd.ZstdCompressor(level=level)
    raw_bytes = 0
    with out_path.open("wb") as fh, cctx.stream_writer(fh) as writer:
        for e in entries:
            line = (to_slim_json(e) + "\n").encode("utf-8")
            raw_bytes += len(line)
            writer.write(line)
    return {
        "raw_bytes": raw_bytes,
        "compressed_bytes": out_path.stat().st_size,
        "sha256": sha256_file(out_path),
    }


def build_pack(input_path: Path, out_dir: Path, core_limit: int, zstd_level: int) -> dict:
    entries = [
        json.loads(line)
        for line in input_path.open(encoding="utf-8")
        if line.strip()
    ]
    out_dir.mkdir(parents=True, exist_ok=True)
    built_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")

    variants = [
        ("full", entries, "coca_learn"),
        ("core20k", entries[:core_limit], "coca_learn_core20k"),
    ]

    artifacts = {}
    for variant_name, subset, prefix in variants:
        db_path = out_dir / f"{prefix}.db"
        db_zst_path = out_dir / f"{prefix}.db.zst"
        jsonl_zst_path = out_dir / f"{prefix}.jsonl.zst"

        counts = build_sqlite(subset, db_path, built_at)
        db_sha = sha256_file(db_path)
        compress_zst(db_path, db_zst_path, zstd_level)
        verify_zst_roundtrip(db_zst_path, db_sha)

        jsonl_meta = write_slim_jsonl_zst(subset, jsonl_zst_path, zstd_level)

        artifacts[variant_name] = {
            "counts": counts,
            "sqlite": {
                "file": db_path.name,
                "bytes": db_path.stat().st_size,
                "sha256": db_sha,
            },
            "sqlite_zst": {
                "file": db_zst_path.name,
                "bytes": db_zst_path.stat().st_size,
                "sha256": sha256_file(db_zst_path),
            },
            "slim_jsonl_zst": {
                "file": jsonl_zst_path.name,
                **jsonl_meta,
            },
        }

    baselines = {}
    if RAW_JSONL.exists():
        baselines["raw_words_jsonl_bytes"] = RAW_JSONL.stat().st_size
    if RAW_MDX.exists():
        baselines["raw_mdx_bytes"] = RAW_MDX.stat().st_size

    full_zst_bytes = artifacts["full"]["sqlite_zst"]["bytes"]
    ratios = {}
    if "raw_words_jsonl_bytes" in baselines:
        ratios["full_db_zst_vs_raw_jsonl"] = round(
            full_zst_bytes / baselines["raw_words_jsonl_bytes"], 4
        )
    if "raw_mdx_bytes" in baselines:
        ratios["full_db_zst_vs_mdx"] = round(
            full_zst_bytes / baselines["raw_mdx_bytes"], 4
        )

    manifest = {
        "schema_version": 2,
        "built_at": built_at,
        "source": str(input_path),
        "zstd_level": zstd_level,
        "core_limit": core_limit,
        "baselines": baselines,
        "ratios": ratios,
        "variants": artifacts,
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def write_freq_asset(entries: list[dict], out_path: Path) -> int:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    words = [e["word"] for e in entries]
    out_path.write_text(
        json.dumps(words, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    return len(words)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--core-limit", type=int, default=20000)
    parser.add_argument("--zstd-level", type=int, default=19)
    parser.add_argument(
        "--write-freq-asset",
        type=Path,
        default=None,
        help="Optional output path for compact COCA word list JSON (e.g. assets/data/coca_60000.json)",
    )
    parser.add_argument(
        "--freq-only",
        action="store_true",
        help="Only write --write-freq-asset without rebuilding SQLite/zstd packs",
    )
    args = parser.parse_args()

    if args.freq_only:
        if args.write_freq_asset is None:
            raise SystemExit("--freq-only requires --write-freq-asset")
        with args.input.open(encoding="utf-8") as fh:
            entries = [json.loads(line) for line in fh if line.strip()]
        count = write_freq_asset(entries, args.write_freq_asset)
        print(f"Wrote {count} ranked words to {args.write_freq_asset}")
        return

    manifest = build_pack(args.input, args.out_dir, args.core_limit, args.zstd_level)
    for name, v in manifest["variants"].items():
        print(
            f"[{name}] {v['counts']['entries']} entries | "
            f"{v['sqlite']['file']}: {v['sqlite']['bytes']/1e6:.2f} MB | "
            f"{v['sqlite_zst']['file']}: {v['sqlite_zst']['bytes']/1e6:.2f} MB | "
            f"{v['slim_jsonl_zst']['file']}: {v['slim_jsonl_zst']['compressed_bytes']/1e6:.2f} MB"
        )
    if args.write_freq_asset is not None:
        with args.input.open(encoding="utf-8") as fh:
            entries = [json.loads(line) for line in fh if line.strip()]
        count = write_freq_asset(entries, args.write_freq_asset)
        print(f"Wrote {count} ranked words to {args.write_freq_asset}")
    print("Ratios:", manifest["ratios"])


if __name__ == "__main__":
    main()
