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
#   apk      build/release/app-<abi>-release.apk               (model bundled)
#
#   tool/package_release.sh windows        # or web / apk / all / install
#   tool/package_release.sh all --no-build # only re-stage the models
#   tool/package_release.sh install        # adb-install the APK for this device
#   tool/package_release.sh apk --publish  # first fold this machine's 自定义
#                                          # library into assets/seed/
#
# `all` builds the three targets at the same time: they write to different trees,
# and on a many-core machine the sequential time was mostly waiting.
#
# The built-in 自定义/AI/收藏 content is baked into the bundle, so what ships is
# the committed `assets/seed/` — not whatever is on the machine running this
# script. `--publish` is the deliberate step that folds this machine's app data
# into it; the tool refuses when this machine has not merged the committed seed
# yet, so a build on another device cannot roll the library back.
#
# Without a model the app still runs: 整句朗读 falls back to the next engine and
# the training UI says which one is in use. This script just makes the shipped
# build the one that has them.
set -uo pipefail

TARGETS=()
BUILD=1
PUBLISH=0

usage() { sed -n '2,28p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    windows|web|apk|all|install) TARGETS+=("$1"); shift ;;
    --no-build) BUILD=0; shift ;;
    --publish) PUBLISH=1; shift ;;
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
ZIP=$MODELS/kokoro.zip
ADB_BIN=${ADB:-adb}

# 1. The models have to be on this machine before anything is packaged.
if ! python tool/fetch_kokoro_model.py --check >/dev/null 2>&1; then
  echo "The Kokoro model is missing. Prepare it once (≈150 MB, kept out of git):" >&2
  echo "  python tool/fetch_kokoro_model.py" >&2
  exit 2
fi
if [ ! -f "$ZIP" ]; then
  echo "packing $ZIP for the Android bundle…"
  python tool/fetch_kokoro_model.py --zip-only
fi

# 2. The built-in library is baked in at build time, so what ships is the
# committed `assets/seed/` — never whatever happens to be on the machine running
# the build. `--publish` is the deliberate step that folds *this* machine's app
# data into it; without the flag a build on another device cannot quietly
# replace (or roll back) the library that was committed.
APP_DATA="${APPDATA:-$HOME/Library/Application Support}/com.example/local_dict"
if [ "$PUBLISH" -eq 1 ]; then
  if [ -f "$APP_DATA/shared_preferences.json" ] || [ -f "$APP_DATA/custom_texts.json" ]; then
    echo "publishing this machine's library into assets/seed…"
    python tool/publish_library.py || { echo "publish failed" >&2; exit 1; }
  else
    echo "no local library at $APP_DATA — nothing to publish, keeping the committed seed"
  fi
else
  echo "keeping the committed seed (pass --publish to fold this machine's library in)"
fi

stage_models() {
  local destination="$1"
  rm -rf "$destination"
  mkdir -p "$destination"
  # Only the model files: kokoro.zip is the Android bundle, not part of a
  # desktop or web deployment.
  cp -r "$MODELS/kokoro" "$destination/"
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

build_target() {
  local target="$1"
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
      # A universal `app-release.apk` left over from an older build has
      # versionCode 1, while the split ones are 1000/2000/3000 + the same code —
      # installing the leftover over a split build fails as a downgrade. Delete
      # it so the only APKs in sight are the ones meant to ship.
      rm -f build/app/outputs/flutter-apk/app-release.apk \
            build/app/outputs/flutter-apk/app-release.apk.sha1
      rm -f "$RELEASE"/*.apk
      cp build/app/outputs/flutter-apk/app-*-release.apk "$RELEASE/"
      cp "$ZIP" "$RELEASE/"
      echo "android: $RELEASE/app-<abi>-release.apk (voices bundled, unpacked on first launch)"
      echo "  install with: tool/package_release.sh install   (picks the phone's ABI)"
      echo "  the zip beside it only updates an install made before bundling"
      du -sh "$RELEASE" 2>/dev/null | sed 's/^/  /'
      ;;
    install)
      # The per-ABI APKs carry different version codes, and installing the wrong
      # one fails as a downgrade (or silently targets the wrong CPU): ask the
      # device which ABI it is.
      if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
        echo "adb not found; set ADB=/path/to/adb" >&2
        return 1
      fi
      local serial=()
      [ -n "${ADB_SERIAL:-}" ] && serial=(-s "$ADB_SERIAL")
      if [ -z "${ADB_SERIAL:-}" ]; then
        local count
        count=$("$ADB_BIN" devices | awk 'NR>1 && $2 == "device"' | wc -l)
        if [ "$count" -ne 1 ]; then
          echo "more than one device is connected; set ADB_SERIAL=<serial>:" >&2
          "$ADB_BIN" devices | tail -n +2 | sed 's/^/  /' >&2
          return 1
        fi
      fi
      local abi apk
      abi=$("$ADB_BIN" "${serial[@]}" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
      case "$abi" in
        arm64*) apk=app-arm64-v8a-release.apk ;;
        armeabi*) apk=app-armeabi-v7a-release.apk ;;
        x86_64*|x86*) apk=app-x86_64-release.apk ;;
        *) echo "unknown device ABI: '${abi}'" >&2; return 1 ;;
      esac
      echo "installing $apk on ${abi:-the device}…"
      "$ADB_BIN" "${serial[@]}" install -r "$RELEASE/$apk"
      ;;
  esac
}

# `all` runs the targets concurrently: each writes its own tree
# (`build/windows`, `build/web`, `build/app`), so nothing races.
run_targets() {
  local targets=("$@")
  if [ "${#targets[@]}" -eq 1 ]; then
    # `return` without the status swallowed a failed build into a clean exit.
    build_target "${targets[0]}"
    return $?
  fi
  local pids=() names=() failed=0
  for target in "${targets[@]}"; do
    build_target "$target" &
    pids+=($!)
    names+=("$target")
  done
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      echo "build failed: ${names[$i]}" >&2
      failed=1
    fi
  done
  return "$failed"
}

if ! run_targets "${TARGETS[@]}"; then
  echo "release failed" >&2
  exit 1
fi

echo
echo "done. what each artefact needs to be shippable:"
printf '  %-8s %s\n' windows "the Release folder as-is (models already inside)"
printf '  %-8s %s\n' web "build/web as-is (models at /tts-models/…)"
printf '  %-8s %s\n' android "one APK for the phone's ABI; the voices are bundled inside it"
