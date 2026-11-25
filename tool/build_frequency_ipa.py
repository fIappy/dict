#!/usr/bin/env python3
"""Rebuild the frequency list: drop obsolete English, attach US/UK IPA.

Output:
  * `assets/data/frequency_ipa.json`   word -> [US IPA, UK IPA]

The ranked word list is not rewritten: the app hides obsolete words at load, so
every remaining word keeps its true COCA rank (see `FrequencyService`).

Sources (tooling only, never shipped as code):
  * US: CMU Pronouncing Dictionary (ARPAbet, converted to broad IPA here).
        A word CMUdict lacks takes the first American IPA printed in the local
        Dictionary.com MDX, when present; what remains is voiced by espeak-ng
        `en-us`.
  * UK: espeak-ng `en-gb-x-rp` (received pronunciation) with stress.

Both accents are broad transcriptions with stress marks, so a learner reads
them in one notation.

Setup once:
  python -m pip install cmudict phonemizer espeakng-loader

Usage:
  python tool/build_frequency_ipa.py             # write both assets
  python tool/build_frequency_ipa.py --dry-run   # report only
  python tool/build_frequency_ipa.py --mdx path/to/dict.mdx
"""

from __future__ import annotations

import argparse
import json
import os
import re
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORDS = os.path.join(ROOT, 'assets', 'data', 'coca_60000.json')
IPA_OUT = os.path.join(ROOT, 'assets', 'data', 'frequency_ipa.json')

# Where espeak-ng's data lives on this machine. The app already ships it beside
# the Kokoro model, so no extra download is needed.
ESPEAK_DATA = os.path.join(ROOT, 'tts-models', 'kokoro')
DEFAULT_MDX = os.path.join(ROOT, 'Dictionary.com 20260913_hahaya',
                           'Dictionary.com 20260913.mdx')

# Purely archaic function words: old pronouns and place adverbs. Modern words
# that merely look archaic stay (`wilt` = plants droop, `art` = the noun,
# `wrought` = wrought iron, `aye` = a yes vote; `ere`/`behold` are literary).
OBSOLETE = (
    'thou', 'thee', 'thy', 'thine', 'ye',
    'whence', 'whither', 'hither', 'thither', 'wherefore',
)

# ARPAbet -> broad IPA. R is /r/, the way learners' dictionaries write it.
ARPABET = {
    'AA': 'ɑ', 'AE': 'æ', 'AH': 'ʌ', 'AO': 'ɔ', 'AW': 'aʊ', 'AY': 'aɪ',
    'EH': 'ɛ', 'ER': 'ɜr', 'EY': 'eɪ', 'IH': 'ɪ', 'IY': 'i', 'OW': 'oʊ',
    'OY': 'ɔɪ', 'UH': 'ʊ', 'UW': 'u',
    'B': 'b', 'CH': 'tʃ', 'D': 'd', 'DH': 'ð', 'F': 'f', 'G': 'ɡ', 'HH': 'h',
    'JH': 'dʒ', 'K': 'k', 'L': 'l', 'M': 'm', 'N': 'n', 'NG': 'ŋ', 'P': 'p',
    'R': 'r', 'S': 's', 'SH': 'ʃ', 'T': 't', 'TH': 'θ', 'V': 'v', 'W': 'w',
    'Y': 'j', 'Z': 'z', 'ZH': 'ʒ',
}
VOWELS = {'AA', 'AE', 'AH', 'AO', 'AW', 'AY', 'EH', 'ER', 'EY', 'IH', 'IY',
          'OW', 'OY', 'UH', 'UW'}
STRESS = {'1': 'ˈ', '2': 'ˌ'}

WORD_RE = re.compile(r"^[a-z][a-z'\- ]*$")
PRON_RE = re.compile(r"<span class='pron'>(.*?)</span>", re.S)
IPA_IN_PRON_RE = re.compile(r"/([^/]+)/")

DIPHTHONGS = ('aʊ', 'aɪ', 'eɪ', 'oʊ', 'ɔɪ')
VOWEL_CHARS = set('ɑæʌɔaɛeiʊuɜɪəo')


def arpabet_to_ipa(phones: list[str]) -> str:
    out: list[str] = []
    for phone in phones:
        stress = ''
        base = phone
        if phone[-1:].isdigit():
            base, digits = phone[:-1], phone[-1]
            stress = STRESS.get(digits, '')
        ipa = ARPABET.get(base)
        if ipa is None:
            continue
        if base in VOWELS:
            if base == 'AH' and not stress:
                ipa = 'ə'
            elif base == 'ER' and not stress:
                # Unstressed ER is the schwa-plus-r of "water": /ər/, not /ɜr/.
                ipa = 'ər'
            out.append(stress + ipa)
        else:
            out.append(ipa)
    return ''.join(out)


def strip_monosyllable_stress(ipa: str) -> str:
    """Dictionaries leave one-syllable words unstressed: /hæv/, not /ˈhæv/."""
    text = ipa
    for diphthong in DIPHTHONGS:
        text = text.replace(diphthong, 'V')
    # A nucleus is a run of vowel symbols: /aʊə/ in "our" is still one syllable.
    syllables = 0
    previous = False
    for ch in text:
        vowel = ch in VOWEL_CHARS or ch == 'V'
        if vowel and not previous:
            syllables += 1
        previous = vowel
    if syllables > 1:
        return ipa
    return ipa.replace('ˈ', '').replace('ˌ', '')


CONSONANT_CHARS = set('bcdfɡhklmnprstvwzjʃʒθðŋ')

# Legal English onsets, longest first. A stress mark moves left over the longest
# legal onset of the stressed syllable — not over the previous syllable's coda
# (`kəmˈpjuːtər`, never `kəˈmpjuːtər`).
ONSETS = tuple(sorted({
    'b', 'd', 'f', 'ɡ', 'h', 'dʒ', 'k', 'l', 'm', 'n', 'p', 'r', 's', 'ʃ',
    't', 'tʃ', 'θ', 'ð', 'v', 'w', 'j', 'z', 'ʒ',
    'pl', 'bl', 'kl', 'ɡl', 'fl', 'sl', 'pr', 'br', 'tr', 'dr', 'kr', 'ɡr',
    'fr', 'θr', 'ʃr', 'pj', 'bj', 'mj', 'fj', 'vj', 'kj', 'ɡj', 'hj',
    'tw', 'dw', 'kw', 'ɡw', 'sw', 'sp', 'st', 'sk', 'sm', 'sn',
    'spl', 'spr', 'str', 'skr', 'skw', 'spj', 'stj', 'skj',
}, key=len, reverse=True))


def place_stress(ipa: str) -> str:
    """Put each stress mark before the stressed syllable's onset.

    The converters emit `tˈitʃər` (mark right before the vowel); IPA and every
    learner's dictionary write /ˈtiːtʃə/, with the mark before the consonant
    that starts the syllable.
    """
    chars = list(ipa)
    i = 0
    while i < len(chars):
        if chars[i] in 'ˈˌ':
            start = i
            while start > 0 and chars[start - 1] in CONSONANT_CHARS:
                start -= 1
            run = ''.join(chars[start:i])
            target = i
            for onset in ONSETS:
                if run.endswith(onset):
                    target = i - len(onset)
                    break
            if target != i:
                mark = chars.pop(i)
                chars.insert(target, mark)
                i = target
        i += 1
    return ''.join(chars)


# Weak forms a learner's dictionary shows instead of the strong citation form.
UK_OVERRIDES = {'a': 'ə'}


def normalize_espeak(ipa: str) -> str:
    """espeak's own symbols -> the broad IPA the app shows."""
    return (ipa.replace('ɹ', 'r').replace('ɚ', 'ər').replace('ɝ', 'ɜr')
               .replace('ɐ', 'ə').replace('ɫ', 'l').replace('ᵻ', 'ɪ')
               .replace('ɾ', 't').strip())


def clean_mdx_ipa(pron: str) -> str:
    """`[waw-ter, wot-er] / ˈwɔ tər, ˈwɒt ər /` -> `ˈwɔtər`."""
    matches = IPA_IN_PRON_RE.findall(pron)
    if not matches:
        return ''
    first = matches[-1].split(',')[0]
    first = first.strip().strip('-').strip()
    return re.sub(r'\s+', '', first)


def mdx_american_ipa(path: str, wanted: set[str]) -> dict[str, str]:
    """First American IPA per headword from the Dictionary.com MDX.

    MDict v2 layout: key blocks give `key -> record offset`; the record blocks
    are then streamed once and only the wanted offsets are decoded.
    """
    if not os.path.exists(path):
        return {}
    with open(path, 'rb') as f:
        header_len = struct.unpack('>I', f.read(4))[0]
        f.read(header_len)
        f.read(4)
        nkb, _entries, _decomp, kbdi_size, kb_size = struct.unpack(
            '>QQQQQ', f.read(40))
        f.read(4)
        kbdi = zlib.decompress(f.read(kbdi_size)[8:])

        p = 0
        infos = []
        for _ in range(nkb):
            count = struct.unpack_from('>Q', kbdi, p)[0]
            p += 8
            first_len = struct.unpack_from('>H', kbdi, p)[0]
            p += 2 + first_len + 1
            last_len = struct.unpack_from('>H', kbdi, p)[0]
            p += 2 + last_len + 1
            comp, decomp = struct.unpack_from('>QQ', kbdi, p)
            p += 16
            infos.append((count, comp, decomp))

        keyoff: dict[int, str] = {}
        for count, comp, _decomp in infos:
            raw = f.read(comp)
            decomp = zlib.decompress(raw[8:])
            q = 0
            for _ in range(count):
                offset = struct.unpack_from('>Q', decomp, q)[0]
                q += 8
                end = decomp.index(b'\x00', q)
                key = decomp[q:end].decode('utf-8', 'replace')
                q = end + 1
                if key.lower() in wanted:
                    keyoff[offset] = key.lower()

        nr = struct.unpack('>Q', f.read(8))[0]
        f.read(24)  # entry count, record-block-info size, total record bytes
        sizes = []
        for _ in range(nr):
            comp, decomp = struct.unpack('>QQ', f.read(16))
            sizes.append((comp, decomp))

        if not keyoff:
            return {}
        result: dict[str, str] = {}
        acc = 0
        last = max(keyoff)
        for comp, decomp_size in sizes:
            if acc > last:
                break
            raw = f.read(comp)
            decomp = zlib.decompress(raw[8:])
            for offset, word in keyoff.items():
                if not (acc <= offset < acc + decomp_size):
                    continue
                local = offset - acc
                end = decomp.find(b'\x00', local)
                if end == -1:
                    end = len(decomp)
                html = decomp[local:end].decode('utf-8', 'replace')
                match = PRON_RE.search(html)
                if match:
                    ipa = clean_mdx_ipa(match.group(1))
                    if ipa:
                        result[word] = ipa
            acc += decomp_size
        return result


def espeak_backend(language: str):
    import espeakng_loader
    espeakng_loader.make_library_available()
    os.environ.setdefault('PHONEMIZER_ESPEAK_LIBRARY',
                          espeakng_loader.get_library_path())
    os.environ.setdefault('PHONEMIZER_ESPEAK_PATH', ESPEAK_DATA)
    os.environ.setdefault('ESPEAK_DATA_PATH', ESPEAK_DATA)
    from phonemizer.backend import EspeakBackend
    return EspeakBackend(language=language, with_stress=True)


def phonemize(backend, words: list[str]) -> dict[str, str]:
    if not words:
        return {}
    raw = backend.phonemize(words, strip=True, njobs=1)
    return {word: normalize_espeak(item) for word, item in zip(words, raw)}


def table_words(words: list[str]) -> set[str]:
    return set(words)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--mdx', default=DEFAULT_MDX)
    args = parser.parse_args()

    with open(WORDS, encoding='utf-8') as f:
        words = [str(w).strip().lower() for w in json.load(f)]
    original = len(words)
    obsolete = set(OBSOLETE)
    removed = [w for w in words if w in obsolete]
    # No IPA for words the app hides: they never reach a row.
    wanted = [w for w in words if w not in obsolete and WORD_RE.match(w)]

    import cmudict
    cmu = cmudict.dict()
    us: dict[str, str] = {}
    from_cmu = 0
    for word in wanted:
        entries = cmu.get(word)
        if entries:
            us[word] = arpabet_to_ipa(entries[0])
            from_cmu += 1

    missing = [w for w in wanted if w not in us]
    from_mdx = mdx_american_ipa(args.mdx, set(missing))
    us.update(from_mdx)
    still = [w for w in wanted if w not in us]
    us.update(phonemize(espeak_backend('en-us'), still))

    uk = phonemize(espeak_backend('en-gb-x-rp'), wanted)
    uk.update({word: value for word, value in UK_OVERRIDES.items()
               if word in table_words(wanted)})

    table: dict[str, list[str]] = {}
    empty: list[str] = []
    for word in wanted:
        pair = [us.get(word, ''), uk.get(word, '')]
        if not pair[0] or not pair[1]:
            empty.append(word)
            continue
        table[word] = [place_stress(strip_monosyllable_stress(pair[0])),
                       place_stress(strip_monosyllable_stress(pair[1]))]

    print(f'words: {original} -> {len(words)} (dropped obsolete: {removed})')
    print(f'ipa entries: {len(table)} | US from CMUdict: {from_cmu} '
          f'| from MDX: {len(from_mdx)} | from espeak: {len(still)}')
    print(f'left without both accents: {len(empty)} (e.g. {empty[:8]})')

    if args.dry_run:
        return 0

    payload = {
        'source': 'CMUdict + Dictionary.com (US) / espeak-ng en-gb-x-rp (UK)',
        'count': len(table),
        'words': table,
    }
    with open(IPA_OUT, 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False, separators=(',', ':'))
        f.write('\n')
    print(f'written: {IPA_OUT} ({os.path.getsize(IPA_OUT)} B)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
