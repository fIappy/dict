#!/usr/bin/env python3
"""Generate the bundled number-word clips in assets/audio/numbers/.

Why clips instead of runtime speech synthesis
---------------------------------------------
Numbers are an open set: nobody can pre-record "1,234,567". What *is* finite is
the vocabulary the spoken form is built from — the words in `NUMBER_WORDS` below
(zero…nine, the teens, the tens, hundred…trillion, the ordinals, point/and/
percent, the month names, …). Each clip holds exactly one word and the app plays
them back to back, so any number speaks offline, with no TTS engine at runtime.

Both accents are recorded (`<word>_uk.wav` / `<word>_us.wav`) because the
*sentence* differs, not just the voice: British keeps the "and" of "one hundred
and twenty-three" and calls a decimal 0 "nought", American drops the "and" and
says "zero".

Cutting a word out of the source recording
-----------------------------------------
The dictionary endpoint returns the word inside a longer file: ~0.4 s of lead-in
silence, occasionally a second take, and — for words that end in a nasal or a
fricative — a long quiet tail ("one" = /wʌn/ decays for ~0.3 s). Two traps cost
a whole regeneration round:

* trimming "silence" at an RMS threshold as high as -40 dB cuts the tail off
  ("one" becomes "wuh") and eats quiet onsets (/w/, /h/, /ð/), and
* `silenceremove` + `areverse` trims from both ends without ever telling you how
  much it removed, so a broken clip still looks like a normal short file.

So the span is measured here, in numpy: 10 ms RMS frames, silence = more than
45 dB below the clip's own peak (floor -60 dB), gaps shorter than 150 ms belong
to the same word, 40 ms of padding on both sides. The samples are then cut,
faded 5 ms at each end, RMS-normalised to -20 dBFS with a -1 dBFS peak ceiling
and encoded as 24 kHz 16-bit mono WAV (PCM, so a sentence can be spliced out of
the clips by joining samples). Every clip is
finally cross-checked against the source recording it came from (Pearson >= 0.95
at the expected offset), so "the wrong span" cannot ship silently.

Sources
-------
`--source youdao` (default) uses the dictionary-voice endpoint the app itself
falls back to for word audio: it returns a native recording per accent
(type=1 British, type=2 American) and covers 120 of the 122 words. The two words
it refuses for one accent (`sixths` / `sevenths`) have no accent-specific
realisation at all, so the other accent's recording is copied for them; the run
reports every such copy.

`--source edge` uses Edge's neural voices and sounds better, but Microsoft now
rejects the client token with HTTP 403, so it only works when that endpoint is
reachable again. Kept because regenerating with it needs no other change.

The vocabulary here is the source of truth for generation; the Dart side mirrors
it in `lib/core/numbers/number_audio.dart`, and `test/widget_test.dart` fails if
the two drift apart, if a clip is missing, or if a reading asks for a word no
clip exists for.

Usage
-----
    python tool/generate_number_audio.py --check            # vocabulary only
    python tool/generate_number_audio.py                    # (re)write all clips
    python tool/generate_number_audio.py --only thirds --force
    python tool/generate_number_audio.py --source edge      # neural voices

Requires ffmpeg on PATH; `--source edge` additionally requires edge-tts.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

import numpy as np

try:  # only needed for --source edge
    import edge_tts
except ImportError:  # pragma: no cover - dependency hint only
    edge_tts = None

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    'assets', 'audio', 'numbers',
)

VOICE_UK = 'en-GB-SoniaNeural'
VOICE_US = 'en-US-JennyNeural'

# Asset key -> text spoken by the voice.
NUMBER_WORDS: dict[str, str] = {
    # ones / teens / tens
    'zero': 'zero', 'one': 'one', 'two': 'two', 'three': 'three', 'four': 'four',
    'five': 'five', 'six': 'six', 'seven': 'seven', 'eight': 'eight', 'nine': 'nine',
    'ten': 'ten', 'eleven': 'eleven', 'twelve': 'twelve', 'thirteen': 'thirteen',
    'fourteen': 'fourteen', 'fifteen': 'fifteen', 'sixteen': 'sixteen',
    'seventeen': 'seventeen', 'eighteen': 'eighteen', 'nineteen': 'nineteen',
    'twenty': 'twenty', 'thirty': 'thirty', 'forty': 'forty', 'fifty': 'fifty',
    'sixty': 'sixty', 'seventy': 'seventy', 'eighty': 'eighty', 'ninety': 'ninety',
    # scales
    'hundred': 'hundred', 'thousand': 'thousand', 'million': 'million',
    'billion': 'billion', 'trillion': 'trillion',
    # ordinals
    'first': 'first', 'second': 'second', 'third': 'third', 'fourth': 'fourth',
    'fifth': 'fifth', 'sixth': 'sixth', 'seventh': 'seventh', 'eighth': 'eighth',
    'ninth': 'ninth', 'tenth': 'tenth', 'eleventh': 'eleventh', 'twelfth': 'twelfth',
    'thirteenth': 'thirteenth', 'fourteenth': 'fourteenth', 'fifteenth': 'fifteenth',
    'sixteenth': 'sixteenth', 'seventeenth': 'seventeenth', 'eighteenth': 'eighteenth',
    'nineteenth': 'nineteenth', 'twentieth': 'twentieth', 'thirtieth': 'thirtieth',
    'fortieth': 'fortieth', 'fiftieth': 'fiftieth', 'sixtieth': 'sixtieth',
    'seventieth': 'seventieth', 'eightieth': 'eightieth', 'ninetieth': 'ninetieth',
    'hundredth': 'hundredth', 'thousandth': 'thousandth', 'millionth': 'millionth',
    # plural fraction denominators (2/3 … 9/10; larger denominators are read
    # "three over twelve" and need no plural form at all)
    'thirds': 'thirds', 'fourths': 'fourths', 'fifths': 'fifths', 'sixths': 'sixths',
    'sevenths': 'sevenths', 'eighths': 'eighths', 'ninths': 'ninths',
    'tenths': 'tenths',
    # function words and units
    # the article in "one and a half" is a word of its own
    'a': 'a',
    'and': 'and', 'point': 'point', 'minus': 'minus', 'plus': 'plus',
    'percent': 'percent', 'over': 'over', 'oh': 'oh', 'nought': 'nought',
    'double': 'double', 'triple': 'triple', 'half': 'half', 'halves': 'halves',
    'quarter': 'quarter', 'quarters': 'quarters', 'times': 'times',
    'degrees': 'degrees', 'nil': 'nil', 'love': 'love', 'nothing': 'nothing',
    # money
    'dollar': 'dollar', 'dollars': 'dollars', 'cent': 'cent', 'cents': 'cents',
    'pound': 'pound', 'pounds': 'pounds', 'penny': 'penny', 'pence': 'pence',
    'euro': 'euro', 'euros': 'euros', 'yuan': 'yuan',
    # clock and calendar
    'oclock': "o'clock", 'to': 'to', 'past': 'past', 'the': 'the', 'of': 'of',
    'in': 'in', 'on': 'on', 'morning': 'morning', 'afternoon': 'afternoon',
    'evening': 'evening', 'night': 'night',
    'monday': 'Monday', 'tuesday': 'Tuesday', 'wednesday': 'Wednesday',
    'thursday': 'Thursday', 'friday': 'Friday', 'saturday': 'Saturday',
    'sunday': 'Sunday',
    # decades and eras: "the nineties", "the two thousands", "500 BC"
    'tens': 'tens', 'twenties': 'twenties', 'thirties': 'thirties', 'forties': 'forties',
    'fifties': 'fifties', 'sixties': 'sixties', 'seventies': 'seventies',
    'eighties': 'eighties', 'nineties': 'nineties',
    'hundreds': 'hundreds', 'thousands': 'thousands',
    'bc': 'BC', 'ad': 'AD',
    # temperature, multiples/frequency and ratios
    'celsius': 'Celsius', 'fahrenheit': 'Fahrenheit', 'below': 'below',
    'degree': 'degree',
    'once': 'once', 'twice': 'twice', 'week': 'week', 'weeks': 'weeks',
    'day': 'day', 'days': 'days', 'month': 'month', 'months': 'months',
    'year': 'year', 'years': 'years', 'every': 'every', 'as': 'as',
    'much': 'much', 'by': 'by', 'out': 'out', 'ratio': 'ratio',
    'january': 'January', 'february': 'February', 'march': 'March', 'april': 'April',
    'may': 'May', 'june': 'June', 'july': 'July', 'august': 'August',
    'september': 'September', 'october': 'October', 'november': 'November',
    'december': 'December',
}

# Words whose pronunciation carries no accent difference at all: when the source
# refuses one accent, the other accent's recording is used and reported.
ACCENT_NEUTRAL = {'sixths', 'sevenths'}

USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'


def fetch_youdao(text: str, accent: str, attempts: int = 3) -> bytes | None:
    """One accent's recording of [text], or None when the endpoint refuses it."""
    voice_type = 1 if accent == 'uk' else 2
    url = 'https://dict.youdao.com/dictvoice?audio=' + urllib.parse.quote(text) + f'&type={voice_type}'
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
            with urllib.request.urlopen(request, timeout=15) as response:
                data = response.read()
            if len(data) > 500:
                return data
        except Exception:  # noqa: BLE001 - retried below
            pass
        time.sleep(0.4 + attempt)
    return None


def fetch_edge(text: str, accent: str, attempts: int = 3) -> bytes | None:
    """Neural-voice audio, written to a temp file first (the API streams)."""
    if edge_tts is None:
        return None
    voice = VOICE_UK if accent == 'uk' else VOICE_US
    for attempt in range(attempts):
        path = os.path.join(tempfile.gettempdir(), f'num_edge_{os.getpid()}_{abs(hash(text))}_{accent}.mp3')
        try:
            asyncio.run(edge_tts.Communicate(text, voice).save(path))
            if os.path.exists(path) and os.path.getsize(path) > 1000:
                data = open(path, 'rb').read()
                os.remove(path)
                return data
        except Exception as exc:  # noqa: BLE001 - retried below
            if attempt == attempts - 1:
                print(f'  ! edge-tts {text} ({voice}): {str(exc)[:80]}', file=sys.stderr)
        time.sleep(0.5)
    return None


SR = 24000
FRAME_MS = 10
SILENCE_DROP_DB = 45.0      # silence = this far below the clip's own peak
SILENCE_FLOOR_DB = -60.0    # ...but never treat quieter-than-this as speech
GAP_MS = 150                # a shorter gap is inside the word, not between takes
MIN_WORD_MS = 120           # anything shorter is a click, not a word
PAD_MS = 40                 # kept on both sides so onsets/tails stay intact
TARGET_RMS_DB = -20.0
PEAK_CEILING_DB = -1.0
FADE_MS = 5


def decode(audio: bytes) -> "np.ndarray":
    """Decode any container ffmpeg reads into float32 mono at [SR]."""
    with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as handle:
        handle.write(audio)
        path = handle.name
    try:
        raw = subprocess.run(
            ['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'],
            capture_output=True, check=True,
        ).stdout
    finally:
        os.remove(path)
    return np.frombuffer(raw, dtype=np.float32)


def utterance_span(x) -> tuple[int, int]:
    """First word in [x] as a sample range, padding included."""
    frame = max(1, int(FRAME_MS / 1000 * SR))
    usable = x[: x.size // frame * frame].reshape(-1, frame)
    if usable.size == 0:
        return 0, x.size
    rms = np.sqrt((usable.astype(np.float64) ** 2).mean(axis=1))
    db = 20 * np.log10(np.maximum(rms, 1e-7))
    # Reference the 95th percentile, not the maximum: a single loud click at the
    # start of a recording would otherwise set the bar so high that the word
    # itself counts as silence ("hundredth" US is a 20 ms blip, 0.5 s of silence,
    # then the word).
    threshold = max(float(np.percentile(db, 95)) - SILENCE_DROP_DB, SILENCE_FLOOR_DB)
    active = np.flatnonzero(db > threshold)
    if active.size == 0:
        return 0, x.size

    # Frames closer together than GAP_MS are one word ("cats" has two energy
    # humps ~120 ms apart; Dictionary.com's multi-take files are >350 ms apart).
    max_gap = int(GAP_MS / FRAME_MS)
    groups: list[list[int]] = [[active[0]]]
    for frame_index in active[1:]:
        if frame_index - groups[-1][-1] > max_gap:
            groups.append([frame_index])
        else:
            groups[-1].append(frame_index)

    # The word is the loudest group long enough to be one — never merely the
    # first, which on a noisy recording is whatever click came before it.
    candidates = [group for group in groups if len(group) * FRAME_MS >= MIN_WORD_MS] or groups
    energy = {id(group): float(np.power(10.0, db[group] / 10.0).sum()) for group in candidates}
    chosen = max(candidates, key=lambda group: energy[id(group)])
    pad = int(PAD_MS / 1000 * SR)
    return max(0, chosen[0] * frame - pad), min(x.size, (chosen[-1] + 1) * frame + pad)


def render(x, span: tuple[int, int]) -> bytes:
    """Cut [span], fade, normalise and encode to 16-bit WAV.

    WAV rather than MP3 because a sentence is *spliced* out of these clips: the
    decoder and the app both join them as PCM, and every platform then plays
    exactly the same bytes. MP3 would need a decoder per platform and its frames
    would leave a seam at every join.
    """
    start, end = span
    segment = x[start:end].astype(np.float64).copy()
    if segment.size == 0:
        raise ValueError('empty span')

    fade = min(int(FADE_MS / 1000 * SR), segment.size // 2)
    if fade > 0:
        ramp = np.linspace(0.0, 1.0, fade)
        segment[:fade] *= ramp
        segment[-fade:] *= ramp[::-1]

    rms = float(np.sqrt((segment ** 2).mean()))
    if rms > 0:
        segment *= (10 ** (TARGET_RMS_DB / 20)) / rms
    ceiling = 10 ** (PEAK_CEILING_DB / 20)
    peak = float(np.abs(segment).max())
    if peak > ceiling:
        segment *= ceiling / peak

    pcm = (segment * 32767.0).astype('<i2').tobytes()
    # Through a real file, so the WAV header carries the exact length.
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as handle:
        path = handle.name
    try:
        subprocess.run(
            ['ffmpeg', '-y', '-v', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '1', '-i', 'pipe:0',
             '-c:a', 'pcm_s16le', '-ac', '1', '-ar', str(SR), '-f', 'wav', path],
            input=pcm, capture_output=True, check=True,
        )
        with open(path, 'rb') as handle:
            return handle.read()
    finally:
        os.remove(path)


def verify(source, clip: bytes, span: tuple[int, int]) -> tuple[bool, str]:
    """The clip must be the source recording of that span, not a mangled copy."""
    a = source.astype(np.float64)
    b = decode(clip).astype(np.float64)
    if b.size == 0:
        return False, 'empty clip'

    span_length = span[1] - span[0]
    # A word that fills its whole recording can decode a few samples longer than
    # the span, so allow up to 80 ms of slack and correlate the overlapping part.
    if not (0.9 * span_length <= b.size <= span_length + int(0.08 * SR)):
        return False, f'length {b.size / SR:.2f}s vs span {span_length / SR:.2f}s'

    tolerance = int(0.05 * SR)
    best = (0.0, span[0])
    for offset in range(max(0, span[0] - tolerance), min(a.size, span[0] + tolerance) + 1, int(0.002 * SR)):
        overlap = min(b.size, a.size - offset)
        if overlap < 0.8 * span_length:
            continue
        window = a[offset:offset + overlap]
        head = b[:overlap]
        denominator = float(np.sqrt((window ** 2).sum()) * np.sqrt((head ** 2).sum()))
        if denominator == 0:
            continue
        correlation = float((window * head).sum() / denominator)
        if correlation > best[0]:
            best = (correlation, offset)

    correlation, offset = best
    if correlation < 0.9:
        return False, f'correlation {correlation:.3f}'
    if abs(offset - span[0]) > tolerance:
        return False, f'offset off by {(offset - span[0]) / SR * 1000:.0f} ms'

    rms_db = 20 * np.log10(max(float(np.sqrt((b ** 2).mean())), 1e-7))
    peak_db = 20 * np.log10(max(float(np.abs(b).max()), 1e-7))
    # A peaky word ("sixth") hits the ceiling and lands below the RMS target;
    # that is the protection working, not a bad clip.
    if not (-30 < rms_db < -16):
        return False, f'rms {rms_db:.1f} dBFS'
    if peak_db > -0.3:
        return False, f'peak {peak_db:.1f} dBFS'
    return True, f'corr {correlation:.3f} rms {rms_db:.1f} dB peak {peak_db:.1f} dB'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='report the vocabulary, write nothing')
    parser.add_argument('--only', default='', help='comma-separated words to (re)generate')
    parser.add_argument('--source', choices=['youdao', 'edge'], default='youdao')
    parser.add_argument('--force', action='store_true', help='regenerate clips that already exist')
    args = parser.parse_args()

    wanted = NUMBER_WORDS
    if args.only:
        keys = [key.strip() for key in args.only.split(',') if key.strip()]
        unknown = [key for key in keys if key not in NUMBER_WORDS]
        if unknown:
            print(f'not in the vocabulary: {", ".join(unknown)}', file=sys.stderr)
            return 2
        wanted = {key: NUMBER_WORDS[key] for key in keys}

    print(f'{len(wanted)} words x 2 accents, source={args.source}')
    if args.check:
        for key, text in wanted.items():
            print(f'  {key:14s} -> {text!r}')
        return 0

    os.makedirs(OUT_DIR, exist_ok=True)
    fetch = fetch_edge if args.source == 'edge' else fetch_youdao
    written = 0
    copied: list[str] = []

    for key, text in wanted.items():
        targets = {accent: os.path.join(OUT_DIR, f'{key}_{accent}.wav') for accent in ('uk', 'us')}
        if not args.force and all(os.path.exists(path) for path in targets.values()):
            continue

        sources: dict[str, bytes] = {}
        for accent in ('uk', 'us'):
            data = fetch(text, accent)
            if data:
                sources[accent] = data

        if len(sources) == 1:
            # One accent refused the word. For an accent-neutral word the other
            # recording is the same sound, so reuse it rather than leave a hole.
            only = next(iter(sources))
            if key in ACCENT_NEUTRAL:
                other = 'us' if only == 'uk' else 'uk'
                sources[other] = sources[only]
                copied.append(f'{key}:{other}<-{only}')
            else:
                print(f'  ! {key}: only {only} available', file=sys.stderr)

        problems: list[str] = []
        for accent, data in sources.items():
            samples = decode(data)
            span = utterance_span(samples)
            if (span[1] - span[0]) < 0.9 * MIN_WORD_MS / 1000 * SR:
                # The endpoint occasionally serves a recording that is mostly
                # silence; shipping it would leave that word silent.
                problems.append(f'{key}_{accent}: source has no word')
                continue
            clip = render(samples, span)
            ok, detail = verify(samples, clip, span)
            if not ok:
                problems.append(f'{key}_{accent}: {detail}')
                # Keep the previous file rather than shipping a broken clip.
                continue
            with open(targets[accent], 'wb') as handle:
                handle.write(clip)
            written += 1
        if problems:
            print(f'  ! {key}: ' + '; '.join(problems), file=sys.stderr)
        print(f'  {key}', flush=True)

    print(f'\nWrote {written} clips into {OUT_DIR}')
    if copied:
        print('Copied across accents (accent-neutral words): ' + ', '.join(copied))
    missing = [
        f'{key}_{accent}'
        for key in NUMBER_WORDS
        for accent in ('uk', 'us')
        if not os.path.exists(os.path.join(OUT_DIR, f'{key}_{accent}.wav'))
    ]
    if missing:
        print(f'Missing clips ({len(missing)}): {", ".join(missing)}', file=sys.stderr)
        return 1
    print('Every clip matches the recording it was cut from.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
