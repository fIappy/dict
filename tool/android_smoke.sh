#!/usr/bin/env bash
# On-device smoke test for the number module's speech engines.
#
# Runs `lib/smoke_main.dart` on a connected phone or emulator and turns its
# `SMOKE …` lines into an exit code. It answers the question a host-side
# `flutter test` cannot: does *this device* turn a number into audio?
#
#   tool/android_smoke.sh                 # the only connected device
#   tool/android_smoke.sh -s PLK110       # pick one of several
#   tool/android_smoke.sh -s emulator-5554 --uninstall
#
# 录音拼接 needs nothing but the bundled assets, so it is checked on a freshly
# installed app; Piper is checked when a model has been installed (use
# `python tool/fetch_piper_models.py --zip-only` and the app's 「安装模型…」
# button) and reported as `skip` when it has not; 系统语音 is asked to say the
# same number. Audio is played on the device, so you also hear the result.
set -uo pipefail

SERIAL=""
UNINSTALL=0
PACKAGE=com.example.local_dict

# This project's toolchain is the Windows/macOS/Linux one, never a WSL install:
# under WSL the Flutter cache belongs to another platform and the build fails
# with "unable to extract Dart SDK".
case "$(uname -r)$(uname -s)" in
  *icrosoft*|*WSL*|*wsl*)
    echo "run this from Windows (Git Bash / MSYS2 / cmd) or from macOS/Linux, not from WSL" >&2
    exit 2
    ;;
esac

# On Windows the SDK's entry point is `flutter.bat`, which a POSIX shell cannot
# execute directly; `//c` keeps the shell from rewriting `/c` into a path.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) FLUTTER=(cmd.exe //c flutter) ;;
  *) FLUTTER=(flutter) ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--serial) SERIAL="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Find a *working* adb: PATH first, then the Windows `where`, then the usual SDK
# locations. The candidate is only accepted if it runs, which rules out the
# Windows store stubs that answer to the name on some machines.
find_adb() {
  local candidate
  for candidate in \
    "$(command -v adb 2>/dev/null)" \
    "$(where.exe adb 2>/dev/null | tr -d '\r' | head -1)" \
    "$(command -v adb.exe 2>/dev/null)" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe" \
    "/d/software/sdk/platform-tools/adb.exe" \
    "/mnt/d/software/sdk/platform-tools/adb.exe" \
    "$HOME/Library/Android/sdk/platform-tools/adb" \
    "/usr/lib/android-sdk/platform-tools/adb"; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    if "$candidate" version >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

ADB="$(find_adb)"
if [ -z "$ADB" ]; then
  echo "no working adb found: put Android platform-tools on PATH (or set ANDROID_SDK_ROOT)" >&2
  exit 2
fi
echo "adb: $ADB"

if [ -z "$SERIAL" ]; then
  mapfile -t DEVICES < <("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')
  if [ "${#DEVICES[@]}" -eq 0 ]; then
    echo "no device connected (adb devices)" >&2
    exit 2
  elif [ "${#DEVICES[@]}" -gt 1 ]; then
    echo "several devices connected, pick one with -s:" >&2
    printf '  %s\n' "${DEVICES[@]}" >&2
    exit 2
  fi
  SERIAL="${DEVICES[0]}"
fi

MODEL=$("$ADB" -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
echo "device: $SERIAL ($MODEL)"

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

# `flutter run` builds, installs and launches, and streams the app's output.
"${FLUTTER[@]}" run -t lib/smoke_main.dart -d "$SERIAL" --debug >"$LOG" 2>&1 &
RUN=$!
trap 'kill $RUN 2>/dev/null; rm -f "$LOG"' EXIT

# The app prints its result within seconds of launching; give the build time
# (first build of the day can take minutes).
for _ in $(seq 1 180); do
  grep -q 'SMOKE done\|SMOKE failed' "$LOG" && break
  kill -0 $RUN 2>/dev/null || break
  sleep 2
done

kill $RUN 2>/dev/null
wait $RUN 2>/dev/null

echo "--- checks ---"
grep -o 'SMOKE .*' "$LOG" | sed 's/^/  /' || true
echo "--------------"

STATUS=1
if grep -q 'SMOKE done' "$LOG"; then
  STATUS=0
elif grep -q 'SMOKE failed' "$LOG"; then
  STATUS=1
else
  echo "the app never reported a result; last output:" >&2
  tail -20 "$LOG" >&2
fi

if [ "$STATUS" -eq 0 ]; then
  echo "PASS ($SERIAL)"
else
  echo "FAIL ($SERIAL)"
fi

if [ "$UNINSTALL" -eq 1 ]; then
  "$ADB" -s "$SERIAL" uninstall "$PACKAGE" >/dev/null 2>&1 && echo "uninstalled from $SERIAL"
fi

exit $STATUS
