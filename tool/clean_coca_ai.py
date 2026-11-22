#!/usr/bin/env python3
"""Clean and normalize content/coca-ai/words.jsonl without modifying the raw file.

Produces:
  - content/coca-ai/words_cleaned.jsonl (schema v2, enriched & denoised)
  - content/coca-ai/clean_report.json   (per-rule counters & audit summary)
"""

import argparse
import collections
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = ROOT / "content" / "coca-ai" / "words.jsonl"
DEFAULT_THEMES = ROOT / "assets" / "data" / "themes.json"
DEFAULT_OUT = ROOT / "content" / "coca-ai" / "words_cleaned.jsonl"
DEFAULT_REPORT = ROOT / "content" / "coca-ai" / "clean_report.json"

SOURCE_TYPOS = {"accomodate", "occurence"}
BOUND_SUFFIXES = {"ade", "ness", "wright", "semitism"}
FOREIGN_OR_DIALECT_NOISE = {"tae", "se"}
REPEATED_CHAR_RE = re.compile(r"(.)\1{2,}")

OFFENSIVE_RE = re.compile(
    r"种族歧视用语|侮辱性称呼|歧视性称呼|歧视性用语|属于严重的?种族歧视|污蔑性称呼|冒犯性极强|只能由黑人使用"
)
VULGAR_RE = re.compile(
    r"(?:这是|属于|(?<![不那满])是)(?:英语里?)?(?:最?常?用?的?|最粗的?|很?重?的?|极度?粗俗的?|粗俗的?)?"
    r"(?:英语)?(?:脏话|粗口|粗话|骂人的?话(?!里)|骂人词|粗俗口语|粗俗说法|粗俗的?口语词|骂人的口语词)"
    r"|脏话的?(?:委婉|缩写|替代)|fucking\s*的委婉|粗俗地指|极度?粗俗|极度侮辱人的骂人话|很粗的骂人话|粗俗俚语|粗俗但很常见|禁忌词|性俚语"
    r"|(?:^|[，：；。])粗俗脏话"
)
INFORMAL_RE = re.compile(
    r"非正式|口语缩写|网络聊天|网络用语|俚语|口语词"
)
FORMAL_RE = re.compile(
    r"医学专用|专业术语|法律术语|偏正式|正式书面|学术用语"
)

ZH_SINGLE_QUOTE_RE = re.compile(
    r"(?<![A-Za-z0-9])'([\u4e00-\u9fff][^'\n]{0,24})'(?![A-Za-z0-9])"
)

TRUE_LY_ADVERB_COMPOUNDS = (
    "dimly-lit",
    "privately-owned",
    "wholly-owned",
    "highly-trained",
    "politically-motivated",
    "newly-elected",
    "newly-formed",
    "democratically-elected",
    "heavily-armed",
    "newly-minted",
    "newly-created",
    "publicly-funded",
    "brightly-colored",
    "naturally-occurring",
    "federally-funded",
    "widely-held",
    "highly-skilled",
    "sexually-transmitted",
)

LINKING_VERB_LY_RE = re.compile(
    r"\b((?:is|was|are|were|be|been|being|seem|seems|seemed|look|looks|looked|"
    r"feel|feels|felt|remain|remains|remained|stay|stays|stayed|become|becomes|"
    r"became|get|gets|got)\s+(?:(?:so|very|quite|still|always|usually|never)\s+)?)"
    r"(" + "|".join(re.escape(w) for w in TRUE_LY_ADVERB_COMPOUNDS) + r")\b",
    re.I,
)

ABBREV_DOT_RE = re.compile(
    r"\b(?:et al|etc|esq|e\.g|i\.e|a\.m|p\.m|vs|mr|mrs|ms|dr|st|jr|sr|"
    r"u\.s|u\.k|inc|ltd|corp|prof|gen|sen|rep|gov)\.$",
    re.I,
)
PATTERN_SLOT_RE = re.compile(r"\b(?:sb|sth|someone|something|one's|doing)\b", re.I)
PATTERN_VING_RE = re.compile(r"(?<![A-Za-z])V-ing(?![A-Za-z])")

FEMALE_NAMES = [
    "Nora", "Claire", "Rachel", "Hannah", "Grace", "Chloe", "Emily", "Julia",
    "Lauren", "Megan", "Sophie", "Alice", "Kate", "Olivia", "Lily", "Ruby",
    "Anna", "Tess", "Erin", "Naomi", "Vera", "Helen", "Lucy", "Molly",
    "Brooke", "Audrey", "Paige", "Tessa", "Natalie", "Diane", "Iris", "Laura",
    "Jen", "Sara", "Beth", "Leah", "Amy", "Zoe", "Abby", "Eva",
]
MALE_NAMES = [
    "Sam", "Owen", "Nate", "Caleb", "Ryan", "Luke", "Noah", "Eli",
    "Adam", "Cole", "Evan", "Paul", "Mark", "Ian", "Joel", "Jack",
    "Max", "Sean", "Drew", "Gabe", "Grant", "Eric", "Scott", "Todd",
    "Greg", "Neil", "Carl", "Dean", "Wade", "Troy", "Alex", "Matt",
    "Seth", "Keith", "Bruce", "Ross",
]

MAYA_KEEP_WORDS = {
    "maya", "mayan", "pre-columbian", "mesoamerican", "yucatan", "aztec", "inca",
}
MAYA_PROTECTED_RE = re.compile(
    r"\b(?:the\s+Maya|ancient\s+Maya|Maya\s+(?:civilization|empire|culture|people|"
    r"ruins|temple|pyramid|calendar|city|cities|king|priest|art|glyph|script)|Mayan)\b",
    re.I,
)
MIA_KEEP_WORDS = {"mia", "mamma"}
MIA_PROTECTED_RE = re.compile(r"\b(?:Mamma\s+Mia|Mia\s+(?:Hamm|Farrow)|MIA)\b")
LEO_KEEP_WORDS = {"leo", "zodiac", "horoscope", "astrology", "constellation", "lion"}
LEO_PROTECTED_CASE_RE = re.compile(
    r"\b(?:Pope\s+Leo|Leo\s+(?:Tolstoy|DiCaprio|Messi|Fender|Burnett))\b"
)
LEO_PROTECTED_CTX_RE = re.compile(
    r"\b(?:zodiac|horoscope|constellation|astrology|sign\s+of\s+Leo)\b",
    re.I,
)


def should_drop(entry: dict, theme_words: set[str]) -> str | None:
    """Return drop reason string if the headword should be excluded, else None."""
    word = str(entry.get("word", "")).strip().lower()
    if word in SOURCE_TYPOS:
        return "source_typo"
    if word in BOUND_SUFFIXES:
        return "bound_suffix"
    if word in FOREIGN_OR_DIALECT_NOISE:
        return "foreign_or_dialect"
    if word == "zz":
        return "elongated_interjection"
    if (
        entry.get("pos") == ["interjection"]
        and REPEATED_CHAR_RE.search(word)
        and word not in theme_words
    ):
        return "elongated_interjection"
    return None


def clean_pos(word: str, pos: list[str], meaning_zh: str) -> list[str]:
    """Normalize known COCA POS tagging artifacts."""
    w = word.strip().lower()
    out: list[str] = []
    for tag in pos:
        if w == "a" and tag == "+infinitive":
            continue
        if w == "to" and tag == "+infinitive":
            mapped = "infinitive"
        else:
            mapped = tag
        if mapped == "preposition" and len(pos) > 1 and "不是介词" in meaning_zh:
            continue
        if mapped not in out:
            out.append(mapped)
    if not out and pos:
        out = [p for p in pos if p != "+infinitive"] or list(pos)
    return out


def classify_register(word: str, pos: list[str], meaning_zh: str) -> str:
    """Classify word register from its Chinese definition."""
    if OFFENSIVE_RE.search(meaning_zh):
        return "offensive"
    if VULGAR_RE.search(meaning_zh):
        return "vulgar"
    first_sent = meaning_zh.split("。")[0]
    if pos == ["interjection"] or INFORMAL_RE.search(first_sent):
        return "informal"
    if FORMAL_RE.search(first_sent):
        return "formal"
    return "standard"


def normalize_en_text(text: str) -> str:
    """Replace smart/curly quotes with ASCII quotes and collapse multi-spaces."""
    cleaned = (
        text.replace("\u201c", '"')
        .replace("\u201d", '"')
        .replace("\u2018", "'")
        .replace("\u2019", "'")
    )
    return re.sub(r" {2,}", " ", cleaned).strip()


def normalize_zh_quotes(text: str) -> str:
    """Convert ASCII straight quotes around Chinese spans into Chinese quotes."""
    return ZH_SINGLE_QUOTE_RE.sub(r"“\1”", text.strip())


def fix_predicate_ly_hyphen(
    text: str, phrases: list[str]
) -> tuple[str, list[str], int]:
    """Un-hyphenate verified -ly adverb compounds in predicate linking-verb slots."""
    replacements: list[tuple[str, str]] = []

    def _sub(match: re.Match[str]) -> str:
        prefix = match.group(1)
        compound = match.group(2)
        unhyphenated = compound.replace("-", " ")
        replacements.append((compound, unhyphenated))
        return prefix + unhyphenated

    updated = LINKING_VERB_LY_RE.sub(_sub, text)
    if not replacements:
        return text, phrases, 0

    new_phrases: list[str] = []
    updated_lower = updated.lower()
    for phrase in phrases:
        candidate = phrase
        if candidate.lower() not in updated_lower:
            for old_c, new_c in replacements:
                candidate = re.sub(re.escape(old_c), new_c, candidate, flags=re.I)
        if candidate.lower() in updated_lower:
            new_phrases.append(candidate)
    return updated, new_phrases, len(replacements)


def _classify_chunk(chunk: str) -> str:
    if "..." in chunk or "…" in chunk:
        return "pattern"
    if PATTERN_SLOT_RE.search(chunk) or PATTERN_VING_RE.search(chunk):
        return "pattern"
    if chunk.endswith(("?", "!")):
        return "expression"
    if chunk.endswith(".") and not ABBREV_DOT_RE.search(chunk):
        return "expression"
    if len(chunk.split()) >= 6:
        return "expression"
    return "collocation"


def clean_and_classify_chunks(
    raw_collocations: list[str],
) -> tuple[list[str], list[str], list[str], int]:
    """Deduplicate collocations, apply verified fixes, and split into 3 classes."""
    seen: set[str] = set()
    collocations: list[str] = []
    patterns: list[str] = []
    expressions: list[str] = []
    dedup_removed = 0

    for raw in raw_collocations:
        item = normalize_en_text(raw)
        if not item:
            continue
        if item.lower() == "support drop precipitously":
            item = "support drops precipitously"
        key = item.lower()
        if key in seen:
            dedup_removed += 1
            continue
        seen.add(key)

        kind = _classify_chunk(item)
        if kind == "pattern":
            patterns.append(item)
        elif kind == "expression":
            expressions.append(item)
        else:
            collocations.append(item)

    return collocations, patterns, expressions, dedup_removed


def _pick_replacement(
    name: str, word: str, pool: list[str], combined_text: str, digest: int
) -> str:
    start = (digest // 35) % len(pool)
    existing_words = set(re.findall(r"[A-Za-z]+", combined_text))
    for offset in range(len(pool)):
        cand = pool[(start + offset) % len(pool)]
        if cand.lower() == word.lower():
            continue
        if cand in existing_words:
            continue
        return cand
    return pool[start]


def diversify_passage_names(
    word: str, title: str, text: str, phrases: list[str]
) -> tuple[str, str, list[str], dict[str, int]]:
    """Deterministically replace overused LLM character names in passages."""
    counts = {"Maya": 0, "Mia": 0, "Leo": 0}
    w_lower = word.strip().lower()
    rules = (
        ("Maya", FEMALE_NAMES, 35, MAYA_KEEP_WORDS, MAYA_PROTECTED_RE, None),
        ("Mia", FEMALE_NAMES, 12, MIA_KEEP_WORDS, MIA_PROTECTED_RE, None),
        ("Leo", MALE_NAMES, 8, LEO_KEEP_WORDS, LEO_PROTECTED_CASE_RE, LEO_PROTECTED_CTX_RE),
    )

    cur_title = title
    cur_text = text
    cur_phrases = list(phrases)

    for name, pool, keep_mod, keep_words, prot_re, ctx_re in rules:
        name_re = re.compile(rf"\b{name}\b")
        if not (name_re.search(cur_title) or name_re.search(cur_text)):
            continue
        if w_lower in keep_words:
            continue
        combined = f"{cur_title} {cur_text}"
        if prot_re.search(combined) or (ctx_re is not None and ctx_re.search(combined)):
            continue
        digest = int.from_bytes(
            hashlib.sha256(f"{name}:{w_lower}".encode("utf-8")).digest()[:8], "big"
        )
        if digest % keep_mod == 0:
            continue

        replacement = _pick_replacement(name, w_lower, pool, combined, digest)
        cur_title = name_re.sub(replacement, cur_title)
        cur_text = name_re.sub(replacement, cur_text)
        cur_phrases = [name_re.sub(replacement, p) for p in cur_phrases]
        counts[name] += 1

    # Preserve verbatim invariant for passage phrases.
    cur_text_lower = cur_text.lower()
    cur_phrases = [p for p in cur_phrases if p.lower() in cur_text_lower]
    return cur_title, cur_text, cur_phrases, counts


def load_theme_lookup(themes_path: Path) -> tuple[set[str], dict[str, tuple[str, str, str]]]:
    """Return (theme_words, word -> (scene_id, scene_label, gloss))."""
    data = json.loads(themes_path.read_text(encoding="utf-8"))
    theme_words: set[str] = set()
    lookup: dict[str, tuple[str, str, str]] = {}
    for scene in data.get("scenes", []):
        sid = scene["id"]
        slabel = scene["label"]
        for group in scene.get("groups", []):
            glosses = group.get("glosses", {})
            for w in group.get("words", []):
                wl = w.lower()
                theme_words.add(wl)
                lookup.setdefault(wl, (sid, slabel, glosses.get(w, "")))
    return theme_words, lookup


def clean_dataset(
    input_path: Path,
    themes_path: Path,
    out_path: Path,
    report_path: Path,
) -> dict:
    """Run full cleaning & enrichment pipeline and write outputs."""
    theme_words, theme_lookup = load_theme_lookup(themes_path)

    dropped_by_reason: collections.Counter[str] = collections.Counter()
    dropped_words: list[dict] = []
    pos_fixed = 0
    register_counts: collections.Counter[str] = collections.Counter()
    ly_fixed = 0
    dedup_removed_total = 0
    chunk_counts: collections.Counter[str] = collections.Counter()
    name_replaced: collections.Counter[str] = collections.Counter()
    name_before: collections.Counter[str] = collections.Counter()
    name_after: collections.Counter[str] = collections.Counter()
    theme_linked = 0
    input_count = 0

    cleaned_entries: list[dict] = []
    with input_path.open(encoding="utf-8") as fh:
        for line in fh:
            if not line.strip():
                continue
            input_count += 1
            raw = json.loads(line)
            reason = should_drop(raw, theme_words)
            if reason is not None:
                assert raw["word"].lower() not in theme_words, (
                    f"Refusing to drop theme word {raw['word']!r}"
                )
                dropped_by_reason[reason] += 1
                dropped_words.append(
                    {"rank": raw["rank"], "word": raw["word"], "reason": reason}
                )
                continue

            word = raw["word"].strip().lower()
            meaning_zh = normalize_zh_quotes(raw["meaning_zh"])
            usage_zh = normalize_zh_quotes(raw["usage_zh"])

            raw_pos = list(raw.get("pos", []))
            new_pos = clean_pos(word, raw_pos, meaning_zh)
            if new_pos != raw_pos:
                pos_fixed += 1

            register = classify_register(word, new_pos, meaning_zh)
            register_counts[register] += 1

            collocs, patterns, expressions, dedups = clean_and_classify_chunks(
                raw.get("collocations", [])
            )
            dedup_removed_total += dedups
            chunk_counts["collocation"] += len(collocs)
            chunk_counts["pattern"] += len(patterns)
            chunk_counts["expression"] += len(expressions)

            cleaned_sentences = []
            for sent in raw.get("sentences", []):
                stext = normalize_en_text(sent["text"])
                sphrases = [normalize_en_text(p) for p in sent.get("phrases", []) if p.strip()]
                stext, sphrases, nfix = fix_predicate_ly_hyphen(stext, sphrases)
                ly_fixed += nfix
                stext_lower = stext.lower()
                sphrases = [p for p in sphrases if p.lower() in stext_lower]
                cleaned_sentences.append(
                    {
                        "text": stext,
                        "translation": sent.get("translation", "").strip(),
                        "phrases": sphrases,
                    }
                )

            raw_psg = raw.get("passage") or {}
            ptitle = normalize_en_text(raw_psg.get("title", ""))
            ptext = normalize_en_text(raw_psg.get("text", ""))
            pphrases = [normalize_en_text(p) for p in raw_psg.get("phrases", []) if p.strip()]
            ptext, pphrases, nfix_p = fix_predicate_ly_hyphen(ptext, pphrases)
            ly_fixed += nfix_p

            for nm in ("Maya", "Mia", "Leo"):
                if re.search(rf"\b{nm}\b", f"{ptitle} {ptext}"):
                    name_before[nm] += 1

            ptitle, ptext, pphrases, rep_counts = diversify_passage_names(
                word, ptitle, ptext, pphrases
            )
            for nm, c in rep_counts.items():
                name_replaced[nm] += c
                if re.search(rf"\b{nm}\b", f"{ptitle} {ptext}"):
                    name_after[nm] += 1

            theme_info = theme_lookup.get(word)
            if theme_info is not None:
                theme_linked += 1
                theme_id, theme_label, theme_gloss = theme_info
            else:
                theme_id, theme_label, theme_gloss = None, None, None

            cleaned_entries.append(
                {
                    "rank": 0,  # Assigned contiguously after filtering.
                    "coca_rank": int(raw["rank"]),
                    "word": word,
                    "source_word": raw["source_word"],
                    "freq": int(raw["freq"]),
                    "pos": new_pos,
                    "theme_id": theme_id,
                    "theme_label": theme_label,
                    "theme_gloss": theme_gloss,
                    "register": register,
                    "meaning_zh": meaning_zh,
                    "usage_zh": usage_zh,
                    "collocations": collocs,
                    "patterns": patterns,
                    "expressions": expressions,
                    "sentences": cleaned_sentences,
                    "passage": {
                        "title": ptitle,
                        "text": ptext,
                        "phrases": pphrases,
                    },
                    "schema": 2,
                    "model": raw.get("model", "deepseek-flash"),
                    "generated_at": raw.get("generated_at", ""),
                }
            )

    for idx, entry in enumerate(cleaned_entries, 1):
        entry["rank"] = idx

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="\n") as fh:
        for entry in cleaned_entries:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")

    report = {
        "input_path": str(input_path),
        "out_path": str(out_path),
        "input_count": input_count,
        "output_count": len(cleaned_entries),
        "dropped_count": len(dropped_words),
        "dropped_by_reason": dict(dropped_by_reason),
        "dropped_words": dropped_words,
        "pos_fixed_count": pos_fixed,
        "register_counts": dict(register_counts),
        "predicate_ly_fixed_count": ly_fixed,
        "dedup_collocations_removed": dedup_removed_total,
        "chunk_counts": dict(chunk_counts),
        "name_diversify": {
            "before_passages": dict(name_before),
            "replaced_passages": dict(name_replaced),
            "after_passages": dict(name_after),
        },
        "theme_linked_count": theme_linked,
    }
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--themes", type=Path, default=DEFAULT_THEMES)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    report = clean_dataset(args.input, args.themes, args.out, args.report)
    print(
        f"Cleaned {report['input_count']} -> {report['output_count']} entries "
        f"(dropped {report['dropped_count']}: {report['dropped_by_reason']})"
    )
    print(f"POS fixed: {report['pos_fixed_count']}, -ly fixes: {report['predicate_ly_fixed_count']}")
    print(f"Chunks: {report['chunk_counts']} (dedup removed: {report['dedup_collocations_removed']})")
    print(f"Registers: {report['register_counts']}")
    print(f"Names diversified: {report['name_diversify']}")
    print(f"Theme linked: {report['theme_linked_count']}")


if __name__ == "__main__":
    main()
