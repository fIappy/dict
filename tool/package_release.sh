#!/usr/bin/env bash
# Build a release and put the Piper models where that build looks for them.
#
# The models (tts-models/, ~35 MB per accent) are runtime resources like the
# dictionaries: not in git, not inside the app where the platform cannot read
# them anyway. Each target reads them from a different place, and this script
# stages them there so the artefact it prints is the thing to ship:
#
#   windows  build/windows/x64/runner/Release/tts-models/     (next to the exe)
#   web      build/web/tts-models/                            (served with the site)
#   apk      build/release/app-release.apk + piper.zip         (imported in-app)
#
#   tool/package_release.sh windows        # or web / apk / all
#   tool/package_release.sh all --no-build # only re-stage the models
#
# Without a model the app still runs: 整句朗读 falls back to the next engine and
# the training UI says which one is in use. This script just makes the shipped
# build the one that has them.
set -uo pipefail

TARGETS=()
BUILD=1

usage() { sed -n '2,18p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    windows|web|apk|all) TARGETS+=("$1"); shift ;;
    --no-build) BUILD=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ "${#TARGETS[@]}" -gt 0 ] || { usage >&2; exit 2; }
[ "${TARGETS[0]}" = "all" ] && TARGETS=(windows web apk)

# Same rule as the smoke test: this project's toolchain is the Windows/macOS/Linux
# one, and a POSIX shell cannot run `flutter.bat` directly.
case "$(uname -r)$(uname -s)" in
  *icrosoft*|*WSL*|*wsl*)
    echo "run this from Windows (Git Bash / MSYS2 / cmd) or macOS/Linux, not from WSL" >&2
    exit 2
    ;;
esac
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) FLUTTER=(cmd.exe //c flutter) ;;
  *) FLUTTER=(flutter) ;;
esac

MODELS=tts-models
ZIP=$MODELS/piper.zip

# 1. The models have to be on this machine before anything is packaged.
if ! python tool/fetch_piper_models.py --check >/dev/null 2>&1; then
  echo "Piper models are missing. Prepare them once (≈70 MB, kept out of git):" >&2
  echo "  python tool/fetch_piper_models.py" >&2
  exit 2
fi
if [ ! -f "$ZIP" ]; then
  echo "packing $ZIP for the Android import…"
  python tool/fetch_piper_models.py --zip-only
fi

stage_models() {
  local destination="$1"
  rm -rf "$destination"
  mkdir -p "$destination"
  # Only the voices: piper.zip is the Android import archive, not part of a
  # desktop or web deployment.
  cp -r "$MODELS/piper" "$destination/"
}

build() {
  local what="$1"
  shift
  if [ "$BUILD" -eq 0 ]; then
    echo "skipping the build (--no-build)"
    return 0
  fi
  echo "building $what…"
  "${FLUTTER[@]}" "$@" || { echo "build failed: $what" >&2; exit 1; }
}

RELEASE=build/release
mkdir -p "$RELEASE"

for target in "${TARGETS[@]}"; do
  case "$target" in
    windows)
      build "Windows (release)" build windows --release
      stage_models "build/windows/x64/runner/Release/$MODELS"
      echo "windows: build/windows/x64/runner/Release/  (ship the whole folder)"
      du -sh build/windows/x64/runner/Release 2>/dev/null | sed 's/^/  /'
      ;;
    web)
      build "Web (release)" build web --release
      stage_models "build/web/$MODELS"
      echo "web: build/web/  (serve it; nginx snippet in docs/WEB_DEPLOYMENT.md §5.3)"
      du -sh build/web 2>/dev/null | sed 's/^/  /'
      ;;
    apk)
      # Per ABI: a universal release APK has to carry sherpa-onnx for four
      # architectures (~280 MB); each phone only needs one of them.
      build "Android APK (release, per ABI)" build apk --release --split-per-abi
      rm -f "$RELEASE"/*.apk
      cp build/app/outputs/flutter-apk/app-*-release.apk "$RELEASE/"
      cp "$ZIP" "$RELEASE/"
      echo "android: $RELEASE/app-<abi>-release.apk + $RELEASE/piper.zip"
      echo "  install the APK, then 数字训练 → Piper 神经语音 → 安装模型… → pick piper.zip"
      du -sh "$RELEASE" 2>/dev/null | sed 's/^/  /'
      ;;
  esac
done

echo
echo "done. what each artefact needs to be shippable:"
printf '  %-8s %s\n' windows "the Release folder as-is (models already inside)"
printf '  %-8s %s\n' web "build/web as-is (models at /tts-models/…)"
printf '  %-8s %s\n' android "one APK for the phone's ABI; models travel as piper.zip (imported once)"
