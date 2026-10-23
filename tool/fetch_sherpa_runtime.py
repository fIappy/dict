"""Fetch the ONNX Runtime that matches the sherpa-onnx build the app links.

`sherpa_onnx_windows` 1.13.8 ships `onnxruntime.dll` 1.17.1 next to a
`sherpa-onnx-c-api.dll` compiled against ONNX Runtime 1.28.2, so every model
fails to load with "requested API version [28] is not available" — and the copy
in System32 shadows anything older anyway. This script drops the matching
runtime into `windows/dlls/`, which `windows/CMakeLists.txt` installs beside the
executable.

Usage:
    python tool/fetch_sherpa_runtime.py
"""

import os
import shutil
import sys
import tarfile
import tempfile
import urllib.request

VERSION = '1.13.8'
ASSET = f'sherpa-onnx-v{VERSION}-win-x64-shared-MD-Release.tar.bz2'
URL = f'https://github.com/k2-fsa/sherpa-onnx/releases/download/v{VERSION}/{ASSET}'

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, 'windows', 'dlls')
WANTED = ['onnxruntime.dll', 'onnxruntime_providers_shared.dll']


def main():
    print(f'downloading {URL}')
    with tempfile.TemporaryDirectory() as tmp:
        archive = os.path.join(tmp, ASSET)
        urllib.request.urlretrieve(URL, archive)
        with tarfile.open(archive, 'r:bz2') as tar:
            tar.extractall(tmp)

        source = None
        for root, _, names in os.walk(tmp):
            if 'onnxruntime.dll' in names:
                source = root
                break
        if source is None:
            sys.exit('onnxruntime.dll not found in the archive')

        os.makedirs(TARGET, exist_ok=True)
        for name in WANTED:
            path = os.path.join(source, name)
            if not os.path.exists(path):
                sys.exit(f'{name} missing from {source}')
            shutil.copy2(path, os.path.join(TARGET, name))
            size = os.path.getsize(path) / 1048576
            print(f'  {name}: {size:.1f} MB')
    print(f'-> {TARGET}')


if __name__ == '__main__':
    main()
