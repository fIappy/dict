"""Fetch the Piper voice models the number module speaks with.

Piper is a small VITS text-to-speech model, run locally by `sherpa_onnx` on
Windows, Android and (as WebAssembly) in the browser — so all three platforms use
the *same* voice for a number, offline. The models are ~20 MB per accent (int8,
which sherpa-onnx's release ships for exactly this) and are not part of the
repository.

Layout written, one folder per accent, addressed by the app on every platform
(the browser cannot list a directory, so the file names are fixed):

    tts-models/piper/us/model.onnx      + tokens.txt + espeak-ng-data/
    tts-models/piper/uk/model.onnx      + tokens.txt + espeak-ng-data/

Usage:
    python tool/fetch_piper_models.py                 # both accents
    python tool/fetch_piper_models.py --only uk       # one accent
    python tool/fetch_piper_models.py --check         # report what is on disk
    python tool/fetch_piper_models.py --voice us=en_US-amy-medium-int8
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

# The voice each accent uses by default. Any `vits-piper-<voice>.tar.bz2` from
# that release works: pass --voice us=… or uk=… to swap it in, then run again.
DEFAULT_VOICES = {
    'us': 'en_US-lessac-medium-int8',
    'uk': 'en_GB-alan-medium-int8',
}

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'tts-models', 'piper')

# What each accent folder must end up with.
REQUIRED = ['model.onnx', 'tokens.txt']

# The list of files the browser build fetches: WebAssembly cannot list a
# directory, and it reads its files from its own file system, so the model is
# loaded by fetching exactly these paths.
MANIFEST = 'files.txt'

# The Android build cannot read a picked folder (scoped storage), so the models
# are also packed into one archive that the app imports in place.
ARCHIVE = os.path.join(os.path.dirname(ROOT), 'piper.zip')


def accent_dir(accent):
    return os.path.join(ROOT, accent)


def write_manifest(accent):
    """List every file of one accent folder, relative to it."""
    folder = accent_dir(accent)
    entries = []
    for root, _, names in os.walk(folder):
        for name in names:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, folder).replace(os.sep, '/')
            if rel != MANIFEST:
                entries.append(rel)
    entries.sort()
    with open(os.path.join(folder, MANIFEST), 'w', encoding='utf-8', newline='\n') as handle:
        handle.write('\n'.join(entries) + '\n')
    return entries


def check():
    """Report which accents have a usable model on disk."""
    ok = True
    for accent in DEFAULT_VOICES:
        folder = accent_dir(accent)
        missing = [name for name in REQUIRED if not os.path.exists(os.path.join(folder, name))]
        if not os.path.isdir(os.path.join(folder, 'espeak-ng-data')):
            missing.append('espeak-ng-data/')
        size = sum(
            os.path.getsize(os.path.join(root, name))
            for root, _, names in os.walk(folder)
            for name in names
        ) if os.path.isdir(folder) else 0
        if not missing:
            # Keep the manifest in step with whatever is on disk.
            entries = write_manifest(accent)
            print(f'{accent}: OK ({size / 1048576:.1f} MB, {len(entries)} files)')
        else:
            print(f'{accent}: missing ' + ', '.join(missing))
        ok = ok and not missing
    return ok


def fetch(accent, voice):
    """Download and lay out one accent's voice."""
    url = f'{RELEASE}/vits-piper-{voice}.tar.bz2'
    target = accent_dir(accent)
    print(f'{accent}: {voice}')
    print(f'  {url}')
    with tempfile.TemporaryDirectory() as tmp:
        archive = os.path.join(tmp, 'voice.tar.bz2')
        urllib.request.urlretrieve(url, archive)
        with tarfile.open(archive, 'r:bz2') as tar:
            tar.extractall(tmp)
        # The tarball holds one folder named after the voice.
        extracted = os.path.join(tmp, f'vits-piper-{voice}')
        if not os.path.isdir(extracted):
            candidates = [os.path.join(tmp, n) for n in os.listdir(tmp)]
            folders = [c for c in candidates if os.path.isdir(c)]
            if len(folders) != 1:
                sys.exit(f'  unexpected archive layout: {os.listdir(tmp)}')
            extracted = folders[0]

        staged = target + '.new'
        shutil.rmtree(staged, ignore_errors=True)
        shutil.copytree(extracted, staged)
        # Fixed names: the browser build addresses these paths without listing
        # the directory, and the app looks for the same names everywhere.
        onnx = [n for n in os.listdir(staged) if n.endswith('.onnx')]
        if len(onnx) != 1:
            sys.exit(f'  expected exactly one .onnx, found {onnx}')
        os.replace(os.path.join(staged, onnx[0]), os.path.join(staged, 'model.onnx'))
        json = os.path.join(staged, onnx[0] + '.json')
        if os.path.exists(json):
            os.replace(json, os.path.join(staged, 'model.onnx.json'))

        shutil.rmtree(target, ignore_errors=True)
        os.replace(staged, target)
    print(f'  -> {target}')


def write_archive():
    """Pack every installed accent into one zip for the in-app import."""
    if not os.path.isdir(ROOT):
        print('nothing to pack')
        return
    with zipfile.ZipFile(ARCHIVE, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for accent in sorted(os.listdir(ROOT)):
            folder = os.path.join(ROOT, accent)
            if not os.path.isdir(folder):
                continue
            for root, _, names in os.walk(folder):
                for name in names:
                    full = os.path.join(root, name)
                    rel = os.path.relpath(full, ROOT).replace(os.sep, '/')
                    archive.write(full, rel)
    print(f'archive: {ARCHIVE} ({os.path.getsize(ARCHIVE) / 1048576:.1f} MB)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=sorted(DEFAULT_VOICES), action='append',
                        help='fetch just this accent (repeatable)')
    parser.add_argument('--voice', action='append', default=[],
                        metavar='ACCENT=VOICE', help='override the voice for one accent')
    parser.add_argument('--check', action='store_true', help='only report what is on disk')
    parser.add_argument('--zip-only', action='store_true',
                        help='only rebuild the archive the Android app imports')
    args = parser.parse_args()

    voices = dict(DEFAULT_VOICES)
    for override in args.voice:
        if '=' not in override:
            sys.exit('--voice expects ACCENT=VOICE')
        accent, voice = override.split('=', 1)
        voices[accent] = voice

    if args.zip_only:
        write_archive()
        sys.exit(0)

    if args.check:
        sys.exit(0 if check() else 1)

    for accent in (args.only or list(voices)):
        fetch(accent, voices[accent])
    if check():
        write_archive()


if __name__ == '__main__':
    main()
