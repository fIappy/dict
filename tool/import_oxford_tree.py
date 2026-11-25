#!/usr/bin/env python3
"""Import Oxford Bookworms (牛津树) PDFs into assets/seed/custom_home.json.

Extracts pure-English main story / article text from FLTRP Oxford Bookworms
PDFs (handles prose, gamebooks, comic-strip translations, and plain bilingual
layouts), strips covers, copyright pages, blurbs, TOCs, ads, glossaries,
activities/exercises, page numbers, and Chinese translations, and writes them
into the Custom section (`自定义栏目`) under the `牛津树` group.

Usage:
  python tool/import_oxford_tree.py --level 0
  python tool/import_oxford_tree.py --level 0 --dry-run
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta
import glob
import json
import os
import re
import sys

import pymupdf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE = r'I:\Downloads\牛津树'
DEFAULT_SEED = os.path.join(ROOT, 'assets', 'seed', 'custom_home.json')
DEFAULT_META = os.path.join(ROOT, 'assets', 'seed', 'custom_home.meta.json')

OXFORD_GROUP_ID = 'grp-oxford-tree'
OXFORD_GROUP_NAME = '牛津树'

BULLET_TOKEN = '\x00BULLET\x00'

# Special glyph codepoints used inside FLTRP LiberationSerif* shifted fonts.
SPECIAL_CHARS: dict[int, str] = {
    0x7E1: '"',
    0x7E2: '"',
    0x7DD: "'",
    0x7DE: "'",
    0x7E8: '...',
    0x7D9: ' — ',
    0x7DA: ' — ',
    0x87A: BULLET_TOKEN,
    0x87B: '',
    0x7D1: ' ',
    0xA9: 'é',
    0x89: 'É',
    0x6A: '©',
    0x77: '·',
    0x64: '£',
    0x70: '°',
    0x36E: 'o',
    0x7DB: ' — ',
    0x7EF: "'",
    0x84A: ' — ',
    0x9C: 'Ü',
    0xBC: 'ü',
    0xA0: 'á',
    0xA1: 'á',
    0xA2: 'â',
    0xA4: 'ä',
    0xA8: 'è',
    0xAB: 'ë',
    0xF1: 'ë',
    0xB6: 'ö',
    0xB8: 'ö',
    0x890: '',
    0x891: '',
}

SMALL_TITLE_WORDS = {
    'a', 'an', 'and', 'as', 'at', 'but', 'by', 'for', 'from',
    'in', 'into', 'nor', 'of', 'on', 'or', 'the', 'to', 'with',
}

KEEP_UPPER_WORDS = {'TV', 'OK', 'CD', 'USA'}

# Fallback English titles only when a PDF itself has no extractable English title
# (e.g. a minimal bilingual handout whose cover wasn't embedded as text).
FALLBACK_EN_TITLES: dict[str, str] = {
    '出租车惊魂': 'Taxi of Terror',
}

FORBIDDEN_BOILERPLATE = (
    'fltrp.com',
    'All rights reserved',
    'Published by arrangement',
    'Originally published by Oxford',
    'Oxford University Press',
    'Before Reading',
    'While Reading',
    'After Reading',
    'GLOSSARY',
    'ACTIVITIES',
    'TRANSLATION',
)

CJK_RE = re.compile(r'[\u2E80-\u9FFF\uF900-\uFAFF\U00020000-\U0002FFFF]')


@dataclass(frozen=True)
class ExtractedBook:
    cn_name: str
    en_title: str
    level: int
    mode: str
    page_range: str
    body: str


@dataclass
class PageLine:
    x0: float
    y0: float
    x1: float
    y1: float
    max_latin_size: float
    latin_text: str
    simsun_text: str
    has_cjk_content: bool
    has_bullet: bool
    is_bold: bool = False


def fnv1a_32_utf16(text: str) -> str:
    """Exact match to CustomTextProvider._fingerprintOf and publish_library.py."""
    u16 = text.encode('utf-16-le')
    h = 0x811C9DC5
    for i in range(0, len(u16), 2):
        h = ((h ^ (u16[i] | (u16[i + 1] << 8))) * 0x01000193) & 0xFFFFFFFF
    return format(h, 'x')


def decode_shifted(text: str, check_unknown: bool = False) -> str:
    """Decode FLTRP LiberationSerif* shifted codepoints into standard text."""
    # A bracketed pronunciation like [məmt...] uses a glyph set with no mapping
    # in these PDFs. It is an annotation, not story text; drop the whole bracket
    # instead of failing the page (and instead of emitting mojibake).
    if '>' in text and '@' in text:
        text = re.sub(
            r'>[^@]*@',
            lambda m: '' if any(ord(c) > 0x7F for c in m.group(0)) else m.group(0),
            text,
        )
    out: list[str] = []
    for ch in text:
        o = ord(ch)
        if o in (0x03, 0x20, 0x09, 0x0D):
            out.append(' ')
        elif 0x04 <= o <= 0x62:
            out.append(chr(o + 29))
        elif o in SPECIAL_CHARS:
            out.append(SPECIAL_CHARS[o])
        else:
            if check_unknown:
                raise ValueError(f'Unknown shifted char {hex(o)} ({ch!r}) in {text!r}')
            out.append(ch)
    return ''.join(out)


def smart_title_case(title: str) -> str:
    """Convert ALL-CAPS PDF titles into clean English title case."""
    cleaned = re.sub(r'\s+', ' ', title).strip()
    if not cleaned:
        return cleaned
    letters = [c for c in cleaned if c.isalpha()]
    if not letters or not all(c.isupper() for c in letters):
        return cleaned
    words = cleaned.split(' ')
    has_leading_num = bool(words and words[0].isdigit())
    out: list[str] = []
    for idx, word in enumerate(words):
        if word in KEEP_UPPER_WORDS:
            out.append(word)
            continue
        lower = word.lower()
        is_edge = (idx == 0) or (idx == len(words) - 1) or (has_leading_num and idx == 1)
        if not is_edge and lower in SMALL_TITLE_WORDS:
            out.append(lower)
            continue
        # Capitalize first alphabetic char, keep remainder lowercase (so "MAN'S" -> "Man's").
        chars = list(lower)
        for ci, c in enumerate(chars):
            if c.isalpha():
                chars[ci] = c.upper()
                break
        out.append(''.join(chars))
    return ' '.join(out)


def parse_shifted_page_lines(page: pymupdf.Page, check_unknown: bool = False) -> list[PageLine]:
    """Extract lines from a PDF page using shifted LiberationSerif spans."""
    raw = page.get_text('dict')
    parsed: list[PageLine] = []
    for block in raw.get('blocks', []):
        if block.get('type') != 0:
            continue
        for ln in block.get('lines', []):
            x0, y0, x1, y1 = ln.get('bbox', (0.0, 0.0, 0.0, 0.0))
            parts: list[str] = []
            simsun_parts: list[str] = []
            has_cjk = False
            has_bullet = False
            max_lat_size = 0.0
            latin_nonempty_spans = 0
            bold_latin_spans = 0
            for sp in ln.get('spans', []):
                font = sp.get('font', '')
                text = sp.get('text', '')
                if 'LiberationSerif' in font:
                    dec = decode_shifted(text, check_unknown=check_unknown)
                    if BULLET_TOKEN in dec:
                        has_bullet = True
                        dec = dec.replace(BULLET_TOKEN, ' ')
                    parts.append(dec)
                    if dec.strip():
                        latin_nonempty_spans += 1
                        if 'Bold' in font:
                            bold_latin_spans += 1
                        max_lat_size = max(max_lat_size, float(sp.get('size', 0.0)))
                else:
                    # In FLTRP PDFs, SimSun U+01C2 ('ǂ') is used purely as a spacer.
                    simsun_parts.append(text)
                    stripped = text.replace('ǂ', '').strip()
                    if stripped:
                        has_cjk = True
                    elif 'ǂ' in text:
                        parts.append(' ')
            latin_text = re.sub(r'[ \t]+', ' ', ''.join(parts)).strip()
            simsun_text = ''.join(simsun_parts).strip()
            if latin_text or simsun_text:
                parsed.append(
                    PageLine(
                        x0=float(x0),
                        y0=float(y0),
                        x1=float(x1),
                        y1=float(y1),
                        max_latin_size=max_lat_size,
                        latin_text=latin_text,
                        simsun_text=simsun_text,
                        has_cjk_content=has_cjk,
                        has_bullet=has_bullet,
                        is_bold=(latin_nonempty_spans > 0 and bold_latin_spans == latin_nonempty_spans),
                    )
                )
    # Visual top-to-bottom, left-to-right reading order.
    parsed.sort(key=lambda l: (round(l.y0 / 4.0), l.x0))
    return parsed


def detect_shifted_boundaries(all_pages: list[list[PageLine]]) -> dict[str, int]:
    """Locate TOC, copyright/ad, GLOSSARY, ACTIVITIES, and TRANSLATION page indices."""
    toc_p: int | None = None
    copy_max = -1
    gloss_p: int | None = None
    act_p: int | None = None
    trans_p: int | None = None

    for i, lines in enumerate(all_pages):
        all_lat = ' '.join(l.latin_text for l in lines if l.latin_text)
        if i < 12 and any(
            ('CONTENTS' in l.latin_text.upper() and l.max_latin_size >= 18)
            or ('ⴞ' in l.simsun_text and 'ᖅ' in l.simsun_text)
            for l in lines
        ):
            if toc_p is None:
                toc_p = i
        if i < 12 and any(
            k in all_lat
            for k in (
                'Copyright',
                'All rights reserved',
                'Originally published by Oxford',
                'Published by arrangement',
                '2u4u.fltrp.com',
                'fltrp.com',
            )
        ):
            copy_max = i
        if i > 10 and any(
            (re.match(r'(?i)^GLOSSARY\b', l.latin_text) is not None
             and l.max_latin_size >= 10)
            or '䇽≷㺘' in l.simsun_text
            for l in lines
        ):
            if gloss_p is None:
                gloss_p = i
        if i > 10 and any(
            (re.match(r'(?i)^(ACTIVITIES|EXERCISES)\b', l.latin_text) is not None
             and l.max_latin_size >= 14)
            or '䰵䈫㓳Ґ' in l.simsun_text
            or (
                ('Before Reading' in l.latin_text or 'While Reading' in l.latin_text)
                and l.max_latin_size >= 18
            )
            for l in lines
        ):
            if act_p is None:
                act_p = i
        if i > 12 and any(
            (re.match(r'(?i)^TRANSLATION\b', l.latin_text) is not None
             and l.max_latin_size >= 10)
            or '৲㘳䈁᮷' in l.simsun_text
            for l in lines
        ):
            if trans_p is None:
                trans_p = i

    return {
        'toc': toc_p if toc_p is not None else -1,
        'copy_max': copy_max,
        'gloss': gloss_p if gloss_p is not None else -1,
        'act': act_p if act_p is not None else -1,
        'trans': trans_p if trans_p is not None else -1,
    }


def extract_toc_title(lines: list[PageLine]) -> str:
    """Pull an English book title from a TOC page if available."""
    skip = {
        'CONTENTS', 'GLOSSARY', 'ACTIVITIES', 'TRANSLATION',
        'ACTIVITIES Before Reading', 'ACTIVITIES While Reading',
        'ACTIVITIES After Reading',
    }
    candidates = [
        l.latin_text
        for l in lines
        if l.latin_text
        and not l.has_cjk_content
        and l.latin_text not in skip
        and not l.latin_text.startswith(('1 ', 'http', 'Before ', 'While ', 'After '))
        and re.search(r'[A-Za-z]', l.latin_text)
    ]
    if len(candidates) == 1:
        return smart_title_case(candidates[0])
    return ''


_WORDS: set[str] | None = None


def known_words() -> set[str]:
    """Lower-case words from the shipped COCA list, loaded once.

    The hyphen at a line break is ambiguous: it either wraps a single word
    ("win-" / "dow") or belongs to a compound ("Ding-" / "dong"). A dictionary
    settles it — the wrapped form is a word, the compound is not.
    """
    global _WORDS
    if _WORDS is None:
        path = os.path.join(ROOT, 'assets', 'data', 'coca_60000.json')
        try:
            with open(path, encoding='utf-8') as f:
                _WORDS = {str(w).strip().lower() for w in json.load(f)}
        except (OSError, ValueError):
            _WORDS = set()
    return _WORDS


def should_dehyphenate(prev: str, nxt: str) -> bool:
    """Only strip a trailing '-' when joining a broken single word, not a compound."""
    if not prev.endswith('-') or not nxt:
        return False
    # Never strip trailing em-dash/spaced hyphen or stutter like 'G-' + 'g-give'
    if prev.endswith((' -', '--', '—')):
        return False
    m = re.search(r'([A-Za-z]+)-$', prev)
    if not m:
        return False
    left = m.group(1)
    first_next = nxt[0]
    if not first_next.isalpha():
        return False
    # Stutter/onomatopoeia like "G-" + "g-give" or "Ding-" + "dong"
    if len(left) <= 2 and nxt.lower().startswith(left.lower()):
        return False
    if not first_next.islower():
        return False
    # "Ding-" + "dong" merges to "dingdong", which is not a word: the hyphen is
    # part of the compound. "win-" + "dow" merges to a word and is only a wrap.
    merged = re.sub(r'[^a-z].*$', '', (left + nxt).lower())
    return merged in known_words()


def join_text_pair(prev: str, nxt: str) -> str:
    """Join two wrapped lines within a paragraph cleanly."""
    if should_dehyphenate(prev, nxt):
        return prev[:-1] + nxt
    if prev.endswith('-'):
        return prev + nxt
    return prev + ' ' + nxt


def ends_sentence(text: str) -> bool:
    t = text.rstrip()
    if not t:
        return False
    return t[-1] in '.!?"\'' or t.endswith(('..."', "...'", '.”', '.”'))


def is_boilerplate_line(text: str) -> bool:
    return any(tok in text for tok in FORBIDDEN_BOILERPLATE) or 'Copyright' in text


def reconstruct_paragraphs(
    page_groups: list[list[PageLine]],
    en_title_hint: str,
    comic_mode: bool = False,
) -> tuple[str, str]:
    """Assemble pure-English lines across pages into clean paragraphs and discover title."""
    captured_title = en_title_hint
    paragraphs: list[str] = []
    cur_para: str = ''

    # Estimate body left margin & right edge across all pure lines for indent/short-line detection.
    body_lines = [
        l for lines in page_groups for l in lines
        if l.latin_text and not l.has_cjk_content and l.max_latin_size < 18
    ]
    left_margin = min((l.x0 for l in body_lines), default=0.0)
    right_edge = max((l.x1 for l in body_lines), default=400.0)
    max_width = max(right_edge - left_margin, 100.0)

    def flush_para() -> None:
        nonlocal cur_para
        if cur_para:
            paragraphs.append(cur_para)
            cur_para = ''

    at_doc_start = True
    prev_line: PageLine | None = None
    prev_had_cjk_gap = False

    for lines in page_groups:
        # Merge adjacent large title/chapter lines at top of page (e.g. "1" + "JOBS FOR TODAY",
        # or 2-line comic title "A Connecticut Yankee in King Arthur's" / "Court").
        i = 0
        # Estimate median/typical left margin per page for multi-column/margin tolerance
        while i < len(lines):
            ln = lines[i]
            if ln.has_cjk_content:
                if comic_mode and cur_para:
                    flush_para()
                prev_had_cjk_gap = True
                i += 1
                continue

            txt = ln.latin_text
            if not txt:
                i += 1
                continue

            # A chapter's word list is set in the same font as the story; it is
            # read as dictionary entries, not prose.
            if _is_gloss_line(txt):
                i += 1
                continue

            # Ignore pure-punctuation lines (e.g. borrowed from CJK quotes/dots) unless ellipsis continuation
            if not re.search(r'[A-Za-z0-9]', txt):
                i += 1
                continue

            # Drop standalone page numbers if tiny/isolated (rare in FLTRP, common if present)
            if re.fullmatch(r'\d{1,3}', txt) and ln.max_latin_size < 16:
                i += 1
                continue

            if txt == 'TRANSLATION' or is_boilerplate_line(txt):
                i += 1
                continue

            # Detect book title / large headings (size >= 20)
            is_big_heading = ln.max_latin_size >= 18.0

            # Gamebook standalone section number before its paragraph (e.g. p8: '1' then 'Oranges in the Snow' or '2' then 'You go...')
            if re.fullmatch(r'\d{1,2}', txt) and ln.max_latin_size >= 18.0:
                # Look ahead to merge multi-line heading or prepend as section marker if next line is body
                if (
                    i + 1 < len(lines)
                    and not lines[i + 1].has_cjk_content
                    and lines[i + 1].max_latin_size >= 18.0
                    and re.search(r'[A-Za-z]', lines[i + 1].latin_text)
                    and abs(lines[i + 1].y0 - ln.y0) < 40
                ):
                    nxt_txt = lines[i + 1].latin_text
                    combined = f'{txt} {smart_title_case(nxt_txt)}'
                    if re.sub(r'\s+', ' ', nxt_txt).strip().lower() == captured_title.lower():
                        # Skip duplicate book title after section '1'
                        combined = f'{txt}.'
                    flush_para()
                    if re.fullmatch(r'\d+\.', combined):
                        cur_para = combined
                    else:
                        paragraphs.append(combined)
                    at_doc_start = False
                    prev_line = lines[i + 1]
                    prev_had_cjk_gap = False
                    i += 2
                    continue
                else:
                    # Standalone section number like "2" / "3"
                    flush_para()
                    cur_para = f'{txt}.'
                    at_doc_start = False
                    prev_line = ln
                    prev_had_cjk_gap = False
                    i += 1
                    continue

            if is_big_heading:
                # Combine multi-line large heading (e.g. 2-line title "A Connecticut Yankee in King Arthur's" / "Court")
                heading_parts = [txt]
                j = i + 1
                while (
                    j < len(lines)
                    and not lines[j].has_cjk_content
                    and lines[j].max_latin_size >= 18.0
                    and not re.fullmatch(r'\d{1,2}', lines[j].latin_text)
                    and abs(lines[j].y0 - lines[j - 1].y1) < ln.max_latin_size * 0.9
                ):
                    heading_parts.append(lines[j].latin_text)
                    j += 1
                heading = re.sub(r'\s+', ' ', ' '.join(heading_parts)).strip()
                heading_tc = smart_title_case(heading)

                # If at very start of story/translation and matches book title (or isn't a numbered chapter), record as title & omit from body.
                is_numbered_chapter = bool(re.match(r'^\d+\b', heading))
                if at_doc_start and not is_numbered_chapter:
                    if not captured_title or len(heading_tc) >= len(captured_title):
                        captured_title = heading_tc
                    at_doc_start = False
                    prev_line = lines[j - 1]
                    prev_had_cjk_gap = False
                    i = j
                    continue

                if captured_title and heading_tc.lower() == captured_title.lower():
                    at_doc_start = False
                    prev_line = lines[j - 1]
                    prev_had_cjk_gap = False
                    i = j
                    continue

                flush_para()
                paragraphs.append(heading_tc)
                at_doc_start = False
                prev_line = lines[j - 1]
                prev_had_cjk_gap = False
                i = j
                continue

            at_doc_start = False

            # Gamebook inline section start like "1Your name..." or "35 You walk..."
            m_sec = re.match(r'^(\d{1,2})\s*([A-Z"\'].*)$', txt)
            starts_game_section = bool(m_sec and not txt.startswith(('19', '20', '16', '18')) and int(m_sec.group(1)) <= 60)
            if starts_game_section and m_sec:
                # Only treat as section header if there isn't a clear year context
                txt = f'{m_sec.group(1)}. {m_sec.group(2)}'

            # Bold section date/banner line (e.g. "AUGUST 15 2030") stands on its own paragraph.
            if ln.is_bold and not ends_sentence(txt) and len(txt) <= 40:
                flush_para()
                paragraphs.append(txt)
                prev_line = ln
                prev_had_cjk_gap = False
                i += 1
                continue

            # Decide whether this line begins a new paragraph
            start_new = False
            if not cur_para:
                start_new = True
            elif ln.has_bullet or starts_game_section:
                start_new = True
            elif comic_mode:
                if prev_had_cjk_gap:
                    start_new = True
                elif prev_line is not None:
                    dy = ln.y0 - prev_line.y1
                    if dy > 10.0 or ends_sentence(cur_para):
                        start_new = True
            elif prev_line is not None:
                # In prose, never break onto a new paragraph if the next line starts lowercase.
                if txt[0].islower():
                    start_new = False
                elif prev_line.is_bold:
                    start_new = True
                # Check if same page vs across page break
                elif ln.y0 < prev_line.y0 - 20.0:
                    # Cross-page boundary: only break paragraph if previous line clearly ended a sentence & wasn't near full width
                    prev_width = prev_line.x1 - prev_line.x0
                    if ends_sentence(cur_para) and (
                        prev_width < max_width * 0.80
                        or txt[0] in '"\''
                    ):
                        start_new = True
                else:
                    dy = ln.y0 - prev_line.y1
                    line_h = max(prev_line.y1 - prev_line.y0, 10.0)
                    prev_width = prev_line.x1 - prev_line.x0
                    if dy > line_h * 0.9:
                        start_new = True
                    elif (ln.x0 - left_margin) > 8.0 and ends_sentence(cur_para):
                        start_new = True
                    elif prev_width < max_width * 0.72 and ends_sentence(cur_para):
                        start_new = True

            # Exception: if cur_para is just a pending gamebook section number ("2."), always join!
            if re.fullmatch(r'\d+\.', cur_para):
                cur_para = f'{cur_para} {txt}'
            elif start_new:
                flush_para()
                cur_para = txt
            else:
                cur_para = join_text_pair(cur_para, txt)

            prev_line = ln
            prev_had_cjk_gap = False
            i += 1

    flush_para()
    body = '\n\n'.join(paragraphs)
    return captured_title, normalize_english_text(body)


def extract_plain_bilingual(doc: pymupdf.Document, cn_name: str) -> ExtractedBook:
    """Extract pure-English paragraphs from an unshifted bilingual PDF (e.g. 出租车惊魂.pdf)."""
    paragraphs: list[str] = []
    cur_para = ''
    prev_was_en = False

    def flush() -> None:
        nonlocal cur_para
        if cur_para:
            paragraphs.append(cur_para)
            cur_para = ''

    for page in doc:
        raw = page.get_text('dict')
        page_lines: list[tuple[float, float, float, float, str]] = []
        for b in raw.get('blocks', []):
            if b.get('type') != 0:
                continue
            for ln in b.get('lines', []):
                text = ''.join(sp.get('text', '') for sp in ln.get('spans', []))
                text = text.replace('￡', '£').strip()
                if not text:
                    continue
                x0, y0, x1, y1 = ln.get('bbox', (0.0, 0.0, 0.0, 0.0))
                page_lines.append((float(y0), float(x0), float(x1), float(y1), text))
        page_lines.sort(key=lambda t: (round(t[0] / 4.0), t[1]))

        prev_y1: float | None = None
        for y0, x0, x1, y1, text in page_lines:
            # Skip standalone page numbers
            if re.fullmatch(r'\d{1,3}', text):
                continue
            if CJK_RE.search(text):
                # Rescue trailing pure-English sound effect after CJK punctuation (e.g. "...！ Bang!")
                m_tail = re.search(r'[！？。…」”\)]\s*([A-Za-z][A-Za-z0-9\s\',.\-!?]+)$', text)
                if prev_was_en:
                    flush()
                    prev_was_en = False
                if m_tail:
                    tail = m_tail.group(1).strip()
                    if re.search(r'[A-Za-z]', tail):
                        paragraphs.append(tail)
                prev_y1 = y1
                continue

            if not re.search(r'[A-Za-z0-9]', text):
                continue

            # Keep standalone all-caps banner headings (e.g. "GOOD LUCK JACK") on their own line.
            if text.isupper() and len(text) <= 40 and not text.endswith(('.', '!', '?')):
                flush()
                paragraphs.append(smart_title_case(text))
                prev_was_en = False
                prev_y1 = y1
                continue

            if cur_para and prev_was_en:
                gap = (y0 - prev_y1) if prev_y1 is not None else 0.0
                if gap > 14.0 and ends_sentence(cur_para):
                    flush()
                    cur_para = text
                else:
                    cur_para = join_text_pair(cur_para, text)
            else:
                flush()
                cur_para = text
            prev_was_en = True
            prev_y1 = y1

    flush()
    en_title = FALLBACK_EN_TITLES.get(cn_name, cn_name)
    body = normalize_english_text('\n\n'.join(paragraphs))
    # Remove redundant banner if it's purely repeated spaces around punctuation
    return ExtractedBook(
        cn_name=cn_name,
        en_title=en_title,
        level=0,
        mode='PLAIN_BILINGUAL',
        page_range=f'0..{len(doc) - 1}',
        body=body,
    )


def normalize_english_text(text: str) -> str:
    """Clean spacing, quotes, dashes, and currency symbols."""
    text = text.replace('“', '"').replace('”', '"').replace('’', "'").replace('‘', "'")
    text = text.replace('–', ' — ').replace('￡', '£')
    text = text.replace('（！）', '')
    text = re.sub(r'£\s+(\d)', r'£\1', text)
    text = re.sub(r'\s*—\s*', ' — ', text)
    text = re.sub(r'[ \t]+', ' ', text)
    # Fix accidental spaces before punctuation inside span joins
    text = re.sub(r' +([,.;:!?])', r'\1', text)
    lines = [ln.strip() for ln in text.splitlines()]
    cleaned = '\n'.join(lines)
    cleaned = re.sub(r'\n{3,}', '\n\n', cleaned)
    return cleaned.strip()




_GLOSS_LINE = re.compile(
    r"^[A-Za-z][A-Za-z' -]{0,40}\s+"
    r"(?:n|v|adj|adv|prep|conj|pron|det|num|phr|excl)\.\s"
)


_GLOSS_TAIL = re.compile(
    r"^\s*(?:n|v|adj|adv|prep|conj|pron|det|num|phr|excl)\.\s"
)


def _is_gloss_line(text: str) -> bool:
    stripped = text.strip()
    return _GLOSS_LINE.match(stripped) is not None or _GLOSS_TAIL.match(stripped) is not None


_CN_TITLES: dict[str, str] = {
    '别了，好莱坞先生': 'Goodbye, Mr Hollywood',
    '在月亮下面': 'Under the Moon',
    '奥米茄文件': 'The Omega Files',
    '歌剧院的幽灵': 'The Phantom of the Opera',
    '爱情与金钱': 'Love or Money?',
    '福尔摩斯和公爵的儿子': "Sherlock Holmes and the Duke's Son",
    '绿野仙踪': 'The Wizard of Oz',
    '苏格兰玛丽女王': 'Mary Queen of Scots',
    '猴爪': "The Monkey's Paw",
    '象人': 'The Elephant Man',
    '雪莉·霍姆斯和立陶宛青年案': 'Shirley Homes and the Lithuanian Case',
    '一个国王的爱情故事': 'The Love of a King',
    '五个孩子和沙精': 'Five Children and It',
    '亡灵岛': "Dead Man's Island",
    '亨利八世和他的六位妻子': 'Henry VIII and His Six Wives',
    '哈克贝利·费恩历险记': 'The Adventures of Huckleberry Finn',
    '威廉·莎士比亚': 'William Shakespeare',
    '爱丽丝漫游奇境记': "Alice's Adventures in Wonderland",
    '鲁宾孙漂流记': 'Robinson Crusoe',
    '格林·盖布尔斯的安妮': 'Anne of Green Gables',
    '圣诞欢歌': 'A Christmas Carol',
    '勃朗特一家的故事': 'The Brontë Story',
    '化学秘密': 'Chemical Secret',
    '曾达的囚徒': 'The Prisoner of Zenda',
    '爱丽丝镜中世界奇遇记': 'Through the Looking-Glass',
    '秘密花园': 'The Secret Garden',
    '野性的呼唤': 'The Call of the Wild',
    '劫机！': 'Skyjack!',
    '多里安·格雷的画像': 'The Picture of Dorian Gray',
    '弗兰肯斯坦': 'Frankenstein',
    '诱拐': 'Kidnapped',
    '三十九级台阶': 'The Thirty-Nine Steps',
    '化身博士': 'Dr Jekyll and Mr Hyde',
    '双城记': 'A Tale of Two Cities',
    '小妇人': 'Little Women',
    '巴斯克维尔猎犬': 'The Hound of the Baskervilles',
    '格列佛游记': "Gulliver's Travels",
    '织工马南': 'Silas Marner',
    '金银岛': 'Treasure Island',
    '黑骏马': 'Black Beauty',
    '三怪客泛舟记': 'Three Men in a Boat',
    '红字': 'The Scarlet Letter',
    '不平静的坟墓': 'The Unquiet Grave',
    '呼啸山庄': 'Wuthering Heights',
    '大卫·科波菲尔': 'David Copperfield',
    '纯真年代': 'The Age of Innocence',
    '远大前程': 'Great Expectations',
    '远离尘嚣': 'Far from the Madding Crowd',
    '傲慢与偏见': 'Pride and Prejudice',
    '名利场': 'Vanity Fair',
    '巴彻斯特教堂尖塔': 'Barchester Towers',
    '白衣女人': 'The Woman in White',
    '简·爱': 'Jane Eyre',
    '苔丝': "Tess of the d'Urbervilles",
    '雾都孤儿': 'Oliver Twist',
    '公正': 'Justice',
    '世界上最冷的地方': 'The Coldest Place on Earth',
    '潘德尔的巫师': 'The Witches of Pendle',
    '爱情故事集：桥及其他': 'The Bridge and Other Love Stories',
    '福尔摩斯与红发会': 'Sherlock Holmes and the Red-Headed League',
    '神秘及幻想故事集': 'The Fall of the House of Usher and Other Stories',
}

_FRONT_MATTER_HEADINGS = (
    'PEOPLE IN THIS STORY',
    'PEOPLE IN THE STORY',
    'THE PEOPLE IN THIS STORY',
    'CHARACTERS IN THIS STORY',
    'CHARACTERS',
    'A FAMILY TREE',
    'INTRODUCTION',
)


def _is_front_matter_page(lines: list[PageLine]) -> bool:
    for line in lines:
        if line.max_latin_size < 18:
            continue
        text = re.sub(r'\s+', ' ', line.latin_text).strip().upper()
        if text in _FRONT_MATTER_HEADINGS:
            return True
    return False


_GENERIC_TITLES = {
    'CONTENTS', 'INTRODUCTION', 'ACTIVITIES', 'EXERCISES', 'GLOSSARY',
    'TRANSLATION', 'PEOPLE IN THIS STORY', 'A FAMILY TREE', 'CHAPTER 1',
    'OXFORD BOOKWORMS LIBRARY', 'OXFORD BOOKWORMS',
}


def extract_cover_title(all_pages: list[list[PageLine]], limit: int) -> str:
    """The English title as printed on the cover or half-title page.

    The TOC trick only works in editions that list the title there; the rest
    land on their Chinese file name. The cover sets the title in the largest
    type of the front matter, often on two lines.
    """
    for page in all_pages[:min(len(all_pages), max(limit, 8))]:
        big = [
            l.latin_text.strip()
            for l in page
            if l.max_latin_size >= 20
            and 2 < len(l.latin_text.strip()) <= 80
            and not l.has_cjk_content
            and re.search(r'[A-Za-z]', l.latin_text)
            and not is_boilerplate_line(l.latin_text)
            and l.latin_text.strip().upper() not in _GENERIC_TITLES
        ]
        if not big:
            continue
        joined = ' '.join(big[:2])
        joined = re.sub(r'\s+', ' ', joined).strip()
        if joined.upper() in _GENERIC_TITLES:
            continue
        return smart_title_case(joined)
    return ''
def extract_book(pdf_path: str, level: int) -> ExtractedBook:
    """Extract a single Oxford Bookworms PDF cleanly according to its detected layout."""
    cn_name = os.path.splitext(os.path.basename(pdf_path))[0]
    doc = pymupdf.open(pdf_path)

    # Check if this PDF uses LiberationSerif shifted encoding.
    has_shifted = any(
        'LiberationSerif' in sp.get('font', '')
        for i in range(min(len(doc), 15))
        for b in doc[i].get_text('dict').get('blocks', [])
        if b.get('type') == 0
        for ln in b.get('lines', [])
        for sp in ln.get('spans', [])
    )
    if not has_shifted:
        book = extract_plain_bilingual(doc, cn_name)
        return ExtractedBook(
            cn_name=book.cn_name,
            en_title=book.en_title,
            level=level,
            mode=book.mode,
            page_range=book.page_range,
            body=book.body,
        )

    all_pages = [parse_shifted_page_lines(page, check_unknown=False) for page in doc]
    marks = detect_shifted_boundaries(all_pages)

    after_front = max(marks['toc'], marks['copy_max']) + 1
    end_candidates = [marks[k] for k in ('gloss', 'act', 'trans') if marks[k] != -1]
    end_story = min(end_candidates) if end_candidates else len(doc)

    def page_counts(i: int) -> tuple[int, int]:
        latin = 0
        cjk = 0
        for line in all_pages[i]:
            latin += len(re.findall(r'[A-Za-z]+', line.latin_text))
            cjk += len(CJK_RE.findall(line.latin_text))
            cjk += len(CJK_RE.findall(line.simsun_text))
        return latin, cjk

    def is_story_page(i: int) -> bool:
        if any(is_boilerplate_line(l.latin_text) for l in all_pages[i]):
            return False
        # "People in This Story" / family trees sit before chapter 1 and are
        # cast lists, not narration.
        if _is_front_matter_page(all_pages[i]):
            return False
        latin, cjk = page_counts(i)
        if latin < 40:
            return False
        # Per-chapter word lists are English, small-ratio Chinese and still not
        # story: they are dictionary entries, one after another.
        lines = [l.latin_text for l in all_pages[i] if l.latin_text.strip()]
        gloss = sum(1 for t in lines if _is_gloss_line(t))
        if gloss >= 3 and gloss * 2 >= len(lines):
            return False
        # A mixed page is front matter, a glossary or the translation section:
        # its Chinese (in any CJK block the fonts use) outweighs the story.
        return cjk <= latin * 0.12

    story_indices = [i for i in range(after_front, end_story) if is_story_page(i)]

    # Cast lists and introductions sit between the TOC and chapter 1; both read
    # as English prose to the page classifier. The story proper starts at the
    # first chapter/part marker, so trim everything before it.
    chapter_marker = re.compile(
        r'(?i)^(\d{1,2}(?:[.\s]|$)|chapter\s+\d|part\s+(one|two|three|four|five))'
    )

    def starts_chapter(i: int) -> bool:
        for line in all_pages[i][:6]:
            text = line.latin_text.strip()
            if line.max_latin_size >= 14 and chapter_marker.match(text):
                return True
        return False

    for offset, page_index in enumerate(story_indices[:6]):
        if starts_chapter(page_index):
            story_indices = story_indices[offset:]
            break
    story_words = sum(
        len(re.findall(r'[A-Za-z]+', l.latin_text))
        for i in story_indices
        for l in all_pages[i]
        if not l.has_cjk_content
    )

    # Some files are several books bound together (one cover / copyright page
    # per book). Importing them as one passage would read like an omnibus; the
    # right fix is splitting the PDF, so say that instead of guessing.
    copyright_pages = sum(
        1
        for i in story_indices
        if any(
            'Originally published by Oxford' in l.latin_text
            or 'registered trademark of Oxford' in l.latin_text
            for l in all_pages[i]
        )
    )
    if copyright_pages > 1:
        raise RuntimeError(
            f'multi-book PDF ({copyright_pages} copyright pages); split it first'
        )
    total_copyright = sum(
        1
        for lines in all_pages
        if any('Originally published by Oxford' in l.latin_text for l in lines)
    )
    if total_copyright > 1:
        raise RuntimeError(
            f'multi-book PDF ({total_copyright} copyright pages); split it first'
        )

    # Look for English title hint from TOC page (after TOC or back cover)
    toc_title = extract_toc_title(all_pages[marks['toc']]) if marks['toc'] != -1 else ''
    # Also check blurb title on page right before TOC (e.g. p6 in 2008/2013 editions)
    blurb_title = ''
    if marks['toc'] > 0:
        for l in all_pages[marks['toc'] - 1]:
            if l.max_latin_size >= 20 and re.search(r'[A-Za-z]', l.latin_text):
                blurb_title = smart_title_case(l.latin_text)
                break
    cover_title = extract_cover_title(all_pages, after_front)
    title_hint = cover_title or toc_title or blurb_title
    if title_hint.strip().upper() in _GENERIC_TITLES:
        title_hint = ''

    if story_words > 200:
        mode = 'PROSE'
        target_indices = story_indices
        comic_mode = False
    else:
        mode = 'COMIC_TRANS'
        trans_start = marks['trans']
        if trans_start == -1:
            raise RuntimeError(f'{pdf_path}: could not locate TRANSLATION section for comic PDF')
        target_indices = list(range(trans_start, len(doc)))
        comic_mode = True

    # Re-parse target pages strictly with unknown char assertion enabled.
    strict_pages = [parse_shifted_page_lines(doc[i], check_unknown=True) for i in target_indices]
    en_title, body = reconstruct_paragraphs(strict_pages, title_hint, comic_mode=comic_mode)
    # The heading the story opens with is a chapter name, not the book: use the
    # cover/TOC hint, a curated English title, and the Chinese name last.
    en_title = _CN_TITLES.get(cn_name) or title_hint or cn_name

    page_range = f'{target_indices[0]}..{target_indices[-1]}'
    return ExtractedBook(
        cn_name=cn_name,
        en_title=en_title,
        level=level,
        mode=mode,
        page_range=page_range,
        body=body,
    )


def validate_book(book: ExtractedBook) -> None:
    """Assert strict cleanliness and quality gates on extracted story text."""
    body = book.body
    if CJK_RE.search(body):
        m = CJK_RE.search(body)
        ctx = body[max(0, m.start() - 25):m.end() + 25]
        raise AssertionError(f'{book.cn_name}: CJK leaked into body near {ctx!r}')
    if '=' in body:
        idx = body.index('=')
        raise AssertionError(f'{book.cn_name}: "=" found in body near {body[max(0, idx-20):idx+20]!r}')
    for forbidden in FORBIDDEN_BOILERPLATE:
        if forbidden in body:
            raise AssertionError(f'{book.cn_name}: forbidden boilerplate {forbidden!r} found')
    words = re.findall(r'[A-Za-z]+', body)
    if len(words) < 500:
        raise AssertionError(f'{book.cn_name}: word count {len(words)} < 500')
    sentences = [s for s in re.split(r'[.!?]+[\s"\']*|\n+', body) if re.search(r'[A-Za-z]', s)]
    if len(sentences) < 30:
        raise AssertionError(f'{book.cn_name}: sentence count {len(sentences)} < 30')
    # Verify only clean characters exist
    allowed_extra = set('\néÉ£—·°áâäèëöüÜ')
    bad_chars = {
        ch for ch in body
        if not (' ' <= ch <= '~' or ch in allowed_extra)
    }
    if bad_chars:
        raise AssertionError(f'{book.cn_name}: unexpected characters {bad_chars!r}')


def update_seed_library(
    books: list[ExtractedBook],
    level: int,
    seed_path: str,
    meta_path: str,
    dry_run: bool,
) -> tuple[int, bool]:
    """Merge extracted books into custom_home.json and recompute custom_home.meta.json."""
    with open(seed_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    groups: list[dict] = list(data.get('groups', []))
    if not any(g.get('id') == OXFORD_GROUP_ID for g in groups):
        groups.append({'id': OXFORD_GROUP_ID, 'name': OXFORD_GROUP_NAME})
    else:
        for g in groups:
            if g.get('id') == OXFORD_GROUP_ID:
                g['name'] = OXFORD_GROUP_NAME

    prefix = f'ox_{level}_'
    existing_texts: list[dict] = [
        t for t in data.get('texts', [])
        if not (t.get('groupId') == OXFORD_GROUP_ID and str(t.get('id', '')).startswith(prefix))
    ]

    base_dt = datetime(2026, 6, level + 1, 0, 0, 0)
    new_entries: list[dict] = []
    for idx, book in enumerate(books, start=1):
        dt = base_dt + timedelta(minutes=idx)
        new_entries.append({
            'id': f'ox_{level}_{idx:02d}',
            'body': book.body,
            'title': f'{book.cn_name} {book.level} · {book.en_title}',
            'groupId': OXFORD_GROUP_ID,
            'createdAt': dt.strftime('%Y-%m-%dT%H:%M:%S.000'),
        })

    merged_texts = existing_texts + new_entries
    changed = (groups != data.get('groups', []) or merged_texts != data.get('texts', []))
    version = int(data.get('version', 1)) + (1 if changed else 0)

    if not dry_run and changed:
        payload = {
            'version': version,
            'groups': groups,
            'texts': merged_texts,
        }
        os.makedirs(os.path.dirname(seed_path), exist_ok=True)
        with open(seed_path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(payload, f, indent=1, ensure_ascii=False)
            f.write('\n')
        with open(seed_path, 'r', encoding='utf-8') as f:
            fp = fnv1a_32_utf16(f.read())
        with open(meta_path, 'w', encoding='utf-8', newline='\n') as f:
            json.dump({'version': version, 'fingerprint': fp}, f, ensure_ascii=False)
            f.write('\n')

    return version, changed


def run_level(source_root: str, level: int, seed_path: str, meta_path: str, dry_run: bool) -> list[ExtractedBook]:
    level_dir = os.path.join(source_root, str(level))
    pdfs = sorted(glob.glob(os.path.join(level_dir, '*.pdf')))
    if not pdfs:
        raise FileNotFoundError(f'No PDFs found in {level_dir}')

    books: list[ExtractedBook] = []
    for index, pdf in enumerate(pdfs, start=1):
        try:
            book = extract_book(pdf, level)
            validate_book(book)
        except Exception as error:  # noqa: BLE001 — one bad PDF must not sink a level
            print(f'  SKIP {os.path.basename(pdf)} (slot {index:02d}): {error}')
            continue
        books.append(book)
    if not books:
        raise RuntimeError(f'Level {level}: no PDF could be extracted')

    version, changed = update_seed_library(books, level, seed_path, meta_path, dry_run)

    print(f'Level {level}: {len(books)} books extracted | seed v{version} ({"updated" if changed and not dry_run else "dry-run" if dry_run else "unchanged"})')
    print('-' * 120)
    for idx, b in enumerate(books, start=1):
        words = len(re.findall(r'[A-Za-z]+', b.body))
        paras = len([p for p in b.body.split('\n\n') if p.strip()])
        first = b.body.splitlines()[0][:55].replace('\n', ' ')
        last = b.body.splitlines()[-1][-55:].replace('\n', ' ')
        print(f'{idx:2d}. ox_{level}_{idx:02d} | {b.cn_name} {level} · {b.en_title} | {b.mode:11s} | p[{b.page_range}] | {words:4d}w | {paras:3d}p')
        print(f'     START: {first!r}')
        print(f'     END:   {last!r}')
    return books


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default=DEFAULT_SOURCE)
    parser.add_argument('--level', type=int, action='append', required=True)
    parser.add_argument('--seed', default=DEFAULT_SEED)
    parser.add_argument('--meta', default=DEFAULT_META)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    for lvl in args.level:
        run_level(args.source, lvl, args.seed, args.meta, args.dry_run)


if __name__ == '__main__':
    main()
