"""Fetch the Kokoro voice the app speaks with.

Kokoro is an 82M-parameter TTS model; sherpa-onnx runs it locally on Windows,
Android and (as WebAssembly) in the browser, so all three platforms use the same
voice, offline. The quantised English build is ~100 MB and is **not** part of the
repository — this script downloads it into `tts-models/kokoro/`:

    tts-models/kokoro/model.onnx       the int8 Kokoro model
    tts-models/kokoro/voices.bin       the speaker embeddings
    tts-models/kokoro/tokens.txt
    tts-models/kokoro/espeak-ng-data/  grapheme-to-phoneme data
    tts-models/kokoro/files.txt        the file list the browser fetches

Usage:
    python tool/fetch_kokoro_model.py            # download and lay out
    python tool/fetch_kokoro_model.py --check    # report what is on disk
    python tool/fetch_kokoro_model.py --zip-only # only rebuild kokoro.zip
"""

import argparse
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

RELEASE = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models'
# v1.x (multi-lingual bundle) is required for real question intonation: the
# English-only v0.19 model falls in pitch on questions as well as statements.
DEFAULT_MODEL = 'kokoro-int8-multi-lang-v1_1'

ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'tts-models', 'kokoro'
)

# What the app addresses by name on every platform.
REQUIRED = ['model.onnx', 'voices.bin', 'tokens.txt', 'lexicon-us-en.txt']

# Only English is spoken here, so the Chinese front end (jieba dictionaries and
# the FST rules) is left out — it is about 50 MB of the download.
UNUSED = ['dict', 'lexicon-zh.txt', 'date-zh.fst', 'number-zh.fst', 'phone-zh.fst']
DATA_FOLDER = 'espeak-ng-data'

# The browser cannot list a directory: it fetches exactly these paths.
MANIFEST = 'files.txt'

# Android cannot read a picked folder (scoped storage), so the model is packed
# into one archive the app unpacks on first use.
ARCHIVE = os.path.join(os.path.dirname(ROOT), 'kokoro.zip')


def write_manifest():
    entries = []
    for root, _, names in os.walk(ROOT):
        for name in names:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, ROOT).replace(os.sep, '/')
            if rel != MANIFEST:
                entries.append(rel)
    entries.sort()
    with open(os.path.join(ROOT, MANIFEST), 'w', encoding='utf-8', newline='\n') as handle:
        handle.write('\n'.join(entries) + '\n')
    return entries


def check():
    missing = [name for name in REQUIRED if not os.path.exists(os.path.join(ROOT, name))]
    if not os.path.isdir(os.path.join(ROOT, DATA_FOLDER)):
        missing.append(DATA_FOLDER + '/')
    if missing:
        print('kokoro: missing ' + ', '.join(missing))
        return False
    size = sum(
        os.path.getsize(os.path.join(root, name))
        for root, _, names in os.walk(ROOT)
        for name in names
    )
    entries = write_manifest()
    print(f'kokoro: OK ({size / 1048576:.1f} MB, {len(entries)} files)')
    return True


def fetch(model):
    url = f'{RELEASE}/{model}.tar.bz2'
    print(f'kokoro: {model}')
    print(f'  {url}')
    with tempfile.TemporaryDirectory() as tmp:
        archive = os.path.join(tmp, 'kokoro.tar.bz2')
        urllib.request.urlretrieve(url, archive)
        with tarfile.open(archive, 'r:bz2') as tar:
            tar.extractall(tmp)

        extracted = os.path.join(tmp, model)
        if not os.path.isdir(extracted):
            folders = [
                os.path.join(tmp, name)
                for name in os.listdir(tmp)
                if os.path.isdir(os.path.join(tmp, name))
            ]
            if len(folders) != 1:
                sys.exit(f'  unexpected archive layout: {os.listdir(tmp)}')
            extracted = folders[0]

        staged = ROOT + '.new'
        shutil.rmtree(staged, ignore_errors=True)
        shutil.copytree(extracted, staged)

        # Fixed names: the browser addresses these paths without listing the
        # directory, and the app looks for the same names everywhere.
        onnx = [name for name in os.listdir(staged) if name.endswith('.onnx')]
        if len(onnx) != 1:
            sys.exit(f'  expected exactly one .onnx, found {onnx}')
        os.replace(os.path.join(staged, onnx[0]), os.path.join(staged, 'model.onnx'))
        voices = [name for name in os.listdir(staged) if name.endswith('.bin')]
        if len(voices) == 1 and voices[0] != 'voices.bin':
            os.replace(os.path.join(staged, voices[0]), os.path.join(staged, 'voices.bin'))
        for extra in ('test.wav', 'README.md', 'LICENSE'):
            path = os.path.join(staged, extra)
            if os.path.exists(path):
                os.remove(path)
        for extra in UNUSED:
            path = os.path.join(staged, extra)
            if os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
            elif os.path.exists(path):
                os.remove(path)

        shutil.rmtree(ROOT, ignore_errors=True)
        os.replace(staged, ROOT)
    print(f'  -> {ROOT}')


def write_archive():
    if not os.path.isdir(ROOT):
        print('nothing to pack')
        return
    with zipfile.ZipFile(ARCHIVE, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for root, _, names in os.walk(ROOT):
            for name in names:
                full = os.path.join(root, name)
                rel = os.path.relpath(full, ROOT).replace(os.sep, '/')
                archive.write(full, rel)
    print(f'archive: {ARCHIVE} ({os.path.getsize(ARCHIVE) / 1048576:.1f} MB)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', default=DEFAULT_MODEL, help='release asset name')
    parser.add_argument('--check', action='store_true', help='only report what is on disk')
    parser.add_argument('--zip-only', action='store_true', help='only rebuild kokoro.zip')
    args = parser.parse_args()

    if args.zip_only:
        write_archive()
        return
    if args.check:
        sys.exit(0 if check() else 1)

    fetch(args.model)
    if check():
        write_archive()


if __name__ == '__main__':
    main()
