#!/usr/bin/env python3
"""Fetch the IPA demonstration clips that Cambridge Dictionary itself plays.

`assets/audio/ipa/<key>_<uk|us>.mp3` is filled from the reference audio of
<https://dictionary.cambridge.org/help/phonetics.html>: the page's
`{uk,us}_phonetics_sound_<example word>_2023feb[_NNN].mp3` files, i.e. the exact
recording you hear when you click a speaker icon next to a symbol on that page.

Every phoneme in `lib/core/ipa/ipa_data.dart` is bound to the Cambridge example
word of its row (`cambridgeExampleWord`), so the clip for `/iː/` is the page's
*sheep* sound, `/ʊ/` is *foot*, `/ɝː/` is the US *bird*, and so on. Cambridge
publishes no reference audio for symbols that are absent from that page, which is
why `--check` fails loudly when the data contains one.

`_uk` / `_us` are only written for the accents Cambridge actually provides: the
page marks some sounds UK-only (/ɒ/ /ɜː/ /əʊ/ /ɪə/ /eə/ /ʊə/) and some US-only
(/ɝː/ /ɚ/ /oʊ/ /t̬/). No clip is ever written from the *word* files
(`*_phonetics_word_*`), only from the isolated-sound ones.

The host sits behind Cloudflare and answers 403 to plain HTTP clients, so the
bytes come from the Wayback Machine's archived copy of the same URL (identical
file, verified by byte size) with a public CORS proxy as the second source.

Usage:
  python tool/fetch_cambridge_ipa_audio.py --check    # report, write nothing
  python tool/fetch_cambridge_ipa_audio.py            # fetch the whole set
  python tool/fetch_cambridge_ipa_audio.py --prune    # also delete stale clips
"""

import argparse
import hashlib
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'lib', 'core', 'ipa', 'ipa_data.dart')
OUT_DIR = os.path.join(ROOT, 'assets', 'audio', 'ipa')

USER_AGENT = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36')
ARCHIVE = 'https://web.archive.org/web/2023id_/'
PROXY = 'https://api.allorigins.win/raw?url='

# Cambridge duplicated the *day* recording; the phoneme rows carry a suffix in
# the page's own markup: /d/ is day_001 (the word "day") and /eɪ/ is day_002.
DAY_SUFFIX = {'d': '001', 'ei': '002'}

ACCENTS = {'both': ('uk', 'us'), 'ukOnly': ('uk',), 'usOnly': ('us',)}

MIN_BYTES = 8000
MAX_BYTES = 200000


class FetchError(RuntimeError):
    pass


def read_data():
    with open(DATA, encoding='utf-8') as stream:
        source = stream.read()
    phonemes = []
    for block in source.split('IpaPhoneme(')[1:]:
        def field(name):
            match = re.search(rf"{name}:\s*'([^']*)'", block)
            return match.group(1) if match else ''
        accent = re.search(r'accent:\s*IpaAccent\.(\w+)', block)
        phonemes.append({
            'key': field('audioAssetKey'),
            'symbol': field('symbol'),
            'word': field('cambridgeExampleWord'),
            'accent': accent.group(1) if accent else 'both',
        })
    if not phonemes:
        raise FetchError(f'no phonemes parsed from {DATA}')
    for phoneme in phonemes:
        if not phoneme['key'] or not phoneme['symbol']:
            raise FetchError(f'incomplete phoneme entry: {phoneme}')
        if not phoneme['word']:
            raise FetchError(f"{phoneme['key']} has no cambridgeExampleWord")
        if phoneme['accent'] not in ACCENTS:
            raise FetchError(f"{phoneme['key']} has unknown accent {phoneme['accent']}")
    keys = [phoneme['key'] for phoneme in phonemes]
    if len(set(keys)) != len(keys):
        raise FetchError('duplicate audioAssetKey in ipa_data.dart')
    return phonemes


def clip_url(word, accent, key):
    suffix = '_' + DAY_SUFFIX[key] if key in DAY_SUFFIX else ''
    name = f'{accent}_phonetics_sound_{word}_2023feb{suffix}.mp3'
    return f'https://dictionary.cambridge.org/media/english/{accent}_phonetic/{name}'


def valid_mp3(payload):
    """Accept only real MPEG audio: an ID3 tag or a frame sync."""
    if payload[:3] == b'ID3':
        return True
    return len(payload) > 2 and payload[0] == 0xFF and (payload[1] & 0xE0) == 0xE0


def download(url, attempts=5):
    sources = [ARCHIVE + url, PROXY + urllib.parse.quote(url, safe='')]
    errors = []
    for source in sources:
        for attempt in range(attempts):
            try:
                request = urllib.request.Request(source, headers={'User-Agent': USER_AGENT})
                with urllib.request.urlopen(request, timeout=60) as response:
                    payload = response.read(MAX_BYTES + 1)
                if response.status != 200:
                    errors.append(f'{source.split("/")[2]}: HTTP {response.status}')
                elif len(payload) < MIN_BYTES or len(payload) > MAX_BYTES:
                    errors.append(f'{source.split("/")[2]}: implausible size {len(payload)}')
                elif not valid_mp3(payload):
                    errors.append(f'{source.split("/")[2]}: not an mp3')
                else:
                    return payload
            except Exception as exc:  # URLError, timeout, reset by the archive
                errors.append(f'{source.split("/")[2]}: {exc}')
            time.sleep(1.0 + attempt)
    raise FetchError('; '.join(errors[-3:]))


def plan(phonemes):
    clips = []
    for phoneme in phonemes:
        for accent in ACCENTS[phoneme['accent']]:
            url = clip_url(phoneme['word'], accent, phoneme['key'])
            if '_phonetics_sound_' not in url:
                raise FetchError(f'refusing non-reference audio for {phoneme["key"]}')
            clips.append({**phoneme, 'accent': accent, 'url': url,
                          'file': f"{phoneme['key']}_{accent}.mp3"})
    return clips


def audit(clips):
    expected = {clip['file'] for clip in clips}
    present = {name for name in os.listdir(OUT_DIR) if name.endswith('.mp3')} if os.path.isdir(OUT_DIR) else set()
    return expected, present, sorted(present - expected), sorted(expected - present)


def report_dead_files(extra_files):
    for name in extra_files:
        path = os.path.join(OUT_DIR, name)
        print(f'  stale {name} ({os.path.getsize(path)} B)')


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--check', action='store_true', help='only report, write nothing')
    parser.add_argument('--prune', action='store_true', help='delete clips not in the plan')
    parser.add_argument('--keys', help='comma separated audioAssetKey subset')
    parser.add_argument('--force', action='store_true', help='re-download clips that already exist')
    parser.add_argument('--sleep', type=float, default=0.4,
                        help='pause between downloads (the archive rate limits)')
    args = parser.parse_args()

    phonemes = read_data()
    every_clip = plan(phonemes)
    clips = every_clip
    if args.keys:
        wanted = {name.strip() for name in args.keys.split(',')}
        clips = [clip for clip in clips if clip['key'] in wanted]
        if not clips:
            raise SystemExit('no phoneme matched --keys')

    # The audit always covers the full set, so `--prune` can never delete clips
    # that a `--keys` subset simply did not look at.
    expected, present, extra_files, missing = audit(every_clip)
    print(f'{len(phonemes)} phonemes, {len(expected)} reference clips')
    if args.keys:
        print(f'fetching subset: {len(clips)} clips')
    print(f'{len(present)} files on disk, {len(missing)} missing, {len(extra_files)} stale')
    if args.prune:
        for name in extra_files:
            os.remove(os.path.join(OUT_DIR, name))
        print(f'pruned {len(extra_files)} stale clips')
    elif extra_files:
        report_dead_files(extra_files)
    if args.check:
        if missing:
            raise SystemExit(f'missing clips: {missing}')
        print('all reference clips present')
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    digests = {}
    failures = []
    for index, clip in enumerate(clips, 1):
        path = os.path.join(OUT_DIR, clip['file'])
        if os.path.exists(path) and os.path.getsize(path) >= MIN_BYTES and not args.force:
            print(f'[{index}/{len(clips)}] {clip["file"]} kept')
        else:
            # Drop the old payload first: a failed download must leave the clip
            # missing (caught by --check and the widget test) instead of leaving a
            # stale TTS clip behind that looks like a valid file.
            if os.path.exists(path):
                os.remove(path)
            try:
                payload = download(clip['url'])
            except FetchError as exc:
                failures.append((clip['file'], str(exc)))
                print(f'[{index}/{len(clips)}] {clip["file"]} FAILED {exc}')
                continue
            with open(path, 'wb') as stream:
                stream.write(payload)
            print(f'[{index}/{len(clips)}] {clip["file"]} {clip["symbol"]} '
                  f'<- {clip["url"].rsplit("/", 1)[-1]} ({len(payload)} B)')
            time.sleep(args.sleep)
        digest = hashlib.sha256(open(path, 'rb').read()).hexdigest()
        twin = digests.get(digest)
        if twin is not None:
            failures.append((clip['file'], f'identical to {twin}'))
        digests[digest] = clip['file']

    for name, reason in failures:
        print(f'FAILED {name}: {reason}', file=sys.stderr)
    if failures:
        raise SystemExit(f'{len(failures)} clip(s) unusable')
    print(f'{len(clips)} reference clips ready in assets/audio/ipa/')


if __name__ == '__main__':
    main()
