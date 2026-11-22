#!/usr/bin/env python3
"""Unit and artifact tests for tool/clean_coca_ai.py and tool/build_coca_pack.py."""

import hashlib
import json
import re
import sqlite3
import sys
import unittest
from pathlib import Path

import zstandard as zstd

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))

import clean_coca_ai as C  # noqa: E402


class CleanRulesUnitTests(unittest.TestCase):
    def test_should_drop_keeps_theme_words_and_drops_noise(self) -> None:
        theme_words = {"mmm", "abandon", "hello"}
        self.assertIsNone(
            C.should_drop({"word": "mmm", "pos": ["interjection"]}, theme_words)
        )
        for noisy in ("accomodate", "occurence", "ade", "ness", "wright", "semitism", "tae", "se", "zz"):
            self.assertIsNotNone(
                C.should_drop({"word": noisy, "pos": ["noun"]}, theme_words),
                msg=f"{noisy} must be dropped",
            )
        self.assertEqual(
            C.should_drop({"word": "aaaaah", "pos": ["interjection"]}, theme_words),
            "elongated_interjection",
        )
        self.assertEqual(
            C.should_drop({"word": "zzz", "pos": ["interjection"]}, theme_words),
            "elongated_interjection",
        )

    def test_clean_pos_fixes_known_coca_artifacts(self) -> None:
        self.assertEqual(C.clean_pos("a", ["article", "+infinitive"], "不定冠词。"), ["article"])
        self.assertEqual(
            C.clean_pos("to", ["+infinitive", "preposition"], "不定式符号。"),
            ["infinitive", "preposition"],
        )
        self.assertEqual(
            C.clean_pos("charge", ["noun", "verb", "preposition"], "名词和动词。charge 本身不是介词。"),
            ["noun", "verb"],
        )
        self.assertEqual(
            C.clean_pos("regards", ["preposition"], "常误用，但单独标注。"),
            ["preposition"],
        )

    def test_classify_register_is_precise_and_avoids_false_positives(self) -> None:
        self.assertEqual(
            C.classify_register("wop", ["noun"], "名词，是对意大利裔人士的侮辱性称呼，属于严重的种族歧视用语。"),
            "offensive",
        )
        self.assertEqual(
            C.classify_register("nigger", ["noun"], "名词，是英语里冒犯性极强的种族歧视用语。"),
            "offensive",
        )
        self.assertEqual(
            C.classify_register("fuck", ["verb"], "动词，是英语里最常用的脏话。"),
            "vulgar",
        )
        self.assertEqual(
            C.classify_register("f-ing", ["adjective"], "形容词，是 fucking 的委婉缩写写法，属于粗俗口语。"),
            "vulgar",
        )
        # Benign words discussing rude speech or race stay standard.
        self.assertEqual(
            C.classify_register("language", ["noun"], "名词，指人类用来交流的语言。使用粗口会冒犯他人。"),
            "standard",
        )
        self.assertEqual(
            C.classify_register("swear", ["verb"], "动词，表示发誓或说脏话。骂人时要注意场合。"),
            "standard",
        )
        self.assertEqual(
            C.classify_register("curse", ["noun", "verb"], "名词和动词，指诅咒或骂人的话。"),
            "standard",
        )
        self.assertEqual(
            C.classify_register("racial", ["adjective"], "形容词，表示种族的、人种的。"),
            "standard",
        )
        self.assertEqual(
            C.classify_register("dural", ["adjective"], "形容词，医学专用，指与硬脑膜有关的。"),
            "formal",
        )

    def test_quote_hygiene_preserves_contractions(self) -> None:
        self.assertEqual(
            C.normalize_en_text("She asked “right?” and don’t go."),
            'She asked "right?" and don\'t go.',
        )
        zh = "名词，'编辑'的意思；注意不要说 it's，而要记住 '一套、一组'。"
        self.assertEqual(
            C.normalize_zh_quotes(zh),
            "名词，“编辑”的意思；注意不要说 it's，而要记住 “一套、一组”。",
        )

    def test_fix_predicate_ly_hyphen_preserves_nouns_and_syncs_phrases(self) -> None:
        text, phrases, fixed = C.fix_predicate_ly_hyphen(
            "The restaurant was dimly-lit inside, not a dimly-lit street.",
            ["was dimly-lit"],
        )
        self.assertEqual(fixed, 1)
        self.assertEqual(text, "The restaurant was dimly lit inside, not a dimly-lit street.")
        self.assertEqual(phrases, ["was dimly lit"])

        # Family-friendly / steely-eyed are NOT -ly adverb compounds and stay hyphenated.
        text2, phrases2, fixed2 = C.fix_predicate_ly_hyphen(
            "The hotel is family-friendly and the coach stayed steely-eyed.",
            ["family-friendly"],
        )
        self.assertEqual(fixed2, 0)
        self.assertIn("family-friendly", text2)
        self.assertIn("steely-eyed", text2)
        self.assertEqual(phrases2, ["family-friendly"])

    def test_clean_and_classify_chunks(self) -> None:
        collocs, patterns, expressions, dedups = C.clean_and_classify_chunks(
            [
                "fall precipitously",
                "Fall Precipitously",
                "support drop precipitously",
                "from ... to ...",
                "avoid doing sth",
                "What's your major?",
                "et al.",
                "in the privacy of your own home",
            ]
        )
        self.assertEqual(dedups, 1)
        self.assertEqual(collocs, ["fall precipitously", "support drops precipitously", "et al."])
        self.assertEqual(patterns, ["from ... to ...", "avoid doing sth"])
        self.assertEqual(
            expressions,
            ["What's your major?", "in the privacy of your own home"],
        )

    def test_diversify_passage_names_protects_cultural_terms(self) -> None:
        title, text, phrases, counts = C.diversify_passage_names(
            "maya",
            "Exploring Ancient Maya Ruins",
            "The ancient Maya built stone cities.",
            ["ancient Maya"],
        )
        self.assertEqual(counts["Maya"], 0)
        self.assertIn("Ancient Maya", title)
        self.assertIn("ancient Maya", text)
        self.assertEqual(phrases, ["ancient Maya"])

        _, ptext2, _, counts2 = C.diversify_passage_names(
            "pope",
            "Rome History",
            "Pope Leo spoke to the crowd.",
            [],
        )
        self.assertEqual(counts2["Leo"], 0)
        self.assertIn("Pope Leo", ptext2)

        # Ordinary character Maya (non-protected) keeps possessives & phrases synchronized.
        _, text3, phrases3, _ = C.diversify_passage_names(
            "coffee",
            "Maya's Morning",
            "Maya grabbed Maya's coffee at noon.",
            ["Maya's coffee"],
        )
        self.assertEqual(len(phrases3), 1)
        self.assertIn(phrases3[0].lower(), text3.lower())


class CleanPackIntegrationTests(unittest.TestCase):
    WORDS_CLEANED = ROOT / "content" / "coca-ai" / "words_cleaned.jsonl"
    REPORT = ROOT / "content" / "coca-ai" / "clean_report.json"
    PACK_DIR = ROOT / "content" / "coca-ai" / "pack"
    THEMES = ROOT / "assets" / "data" / "themes.json"

    def test_cleaned_jsonl_invariants(self) -> None:
        with self.WORDS_CLEANED.open(encoding="utf-8") as fh:
            entries = [json.loads(l) for l in fh if l.strip()]
        report = json.loads(self.REPORT.read_text(encoding="utf-8"))
        self.assertEqual(len(entries), report["output_count"])

        # Contiguous ranks & strictly non-increasing frequency
        for idx, e in enumerate(entries, 1):
            self.assertEqual(e["rank"], idx)
        self.assertTrue(all(a["freq"] >= b["freq"] for a, b in zip(entries, entries[1:])))

        # Zero dropped words & full theme overlap
        word_map = {e["word"]: e for e in entries}
        for dropped in ("accomodate", "occurence", "ade", "ness", "wright", "semitism", "tae", "se", "aaaaah", "zzz"):
            self.assertNotIn(dropped, word_map)
        self.assertIn("mmm", word_map)

        themes = json.loads(self.THEMES.read_text(encoding="utf-8"))
        theme_words = {
            w.lower()
            for sc in themes["scenes"]
            for g in sc["groups"]
            for w in g["words"]
        }
        overlap = theme_words & set(word_map)
        self.assertEqual(len(overlap), 17574)
        for w in overlap:
            self.assertIsNotNone(word_map[w]["theme_id"], msg=f"{w} missing theme_id")

        # Hygiene invariants across every cleaned entry
        maya_passages = 0
        for e in entries:
            self.assertNotIn("+infinitive", e["pos"])
            self.assertFalse(C.ZH_SINGLE_QUOTE_RE.search(e["meaning_zh"]))
            self.assertFalse(C.ZH_SINGLE_QUOTE_RE.search(e["usage_zh"]))

            all_chunks = e["collocations"] + e["patterns"] + e["expressions"]
            self.assertEqual(len({c.lower() for c in all_chunks}), len(all_chunks))

            en_fields = list(all_chunks) + [e["passage"]["title"], e["passage"]["text"]]
            for s in e["sentences"]:
                en_fields.append(s["text"])
                for p in s["phrases"]:
                    self.assertIn(p.lower(), s["text"].lower())
            for p in e["passage"]["phrases"]:
                self.assertIn(p.lower(), e["passage"]["text"].lower())
            joined_en = " ".join(en_fields)
            for ch in ("“", "”", "‘", "’"):
                self.assertNotIn(ch, joined_en)
            if re.search(r"\bMaya\b", f"{e['passage']['title']} {e['passage']['text']}"):
                maya_passages += 1

        self.assertLess(maya_passages, 250)
        self.assertIn("ancient Maya", word_map["maya"]["passage"]["text"])
        for w in ("wop", "nigger", "nigga", "darky", "bitch"):
            self.assertEqual(word_map[w]["register"], "offensive", msg=w)
        for w in (
            "fuck", "fucking", "f-ing", "eff", "bullshit", "asshole",
            "goddamn", "motherfucker", "shit", "cunt", "bastard", "shitty", "piss", "slut",
        ):
            self.assertEqual(word_map[w]["register"], "vulgar", msg=w)
        for w in (
            "language", "swear", "curse", "death", "green", "warning",
            "racial", "pg-rated", "four-letter", "pig", "lowly", "jalopy",
            "unmentionable", "misfit", "profanity-laced",
        ):
            self.assertEqual(word_map[w]["register"], "standard", msg=w)

    def test_sqlite_and_zstd_pack_integrity(self) -> None:
        manifest = json.loads((self.PACK_DIR / "manifest.json").read_text(encoding="utf-8"))
        for variant in ("full", "core20k"):
            meta_v = manifest["variants"][variant]
            db_path = self.PACK_DIR / meta_v["sqlite"]["file"]
            zst_path = self.PACK_DIR / meta_v["sqlite_zst"]["file"]
            self.assertTrue(db_path.is_file())
            self.assertTrue(zst_path.is_file())

            con = sqlite3.connect(db_path)
            try:
                self.assertEqual(con.execute("PRAGMA integrity_check").fetchone()[0], "ok")
                lex_cnt = con.execute("SELECT COUNT(*) FROM lexemes").fetchone()[0]
                chk_cnt = con.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
                snt_cnt = con.execute("SELECT COUNT(*) FROM sentences").fetchone()[0]
                meta_tbl = dict(con.execute("SELECT key, value FROM meta").fetchall())
                self.assertEqual(lex_cnt, meta_v["counts"]["entries"])
                self.assertEqual(chk_cnt, meta_v["counts"]["chunks"])
                self.assertEqual(snt_cnt, meta_v["counts"]["sentences"])
                self.assertEqual(int(meta_tbl["entry_count"]), lex_cnt)
            finally:
                con.close()

            dctx = zstd.ZstdDecompressor()
            h = hashlib.sha256()
            with zst_path.open("rb") as fin, dctx.stream_reader(fin) as reader:
                while chunk := reader.read(1024 * 1024):
                    h.update(chunk)
            self.assertEqual(h.hexdigest(), meta_v["sqlite"]["sha256"])


if __name__ == "__main__":
    unittest.main()
