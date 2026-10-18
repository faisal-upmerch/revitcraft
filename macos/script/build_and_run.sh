#!/usr/bin/env bash
# Builds Arcus, stages build/Arcus.app, validates the bundle and launches it.
#
#   script/build_and_run.sh               release build, stage, validate, launch
#   script/build_and_run.sh --verify      clean-ish verify: run all tests, build, validate, launch, confirm a GUI window
#   script/build_and_run.sh --no-launch   build and stage only
#   script/build_and_run.sh --debug       debug configuration
#   script/build_and_run.sh --release-build  use BUILD_NUMBER exactly (used by release_local.sh)
#
# Requires Xcode 26+ command line tools (swift, codesign, iconutil, plutil). No Homebrew, Python or network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
APP_NAME="Arcus"
BUNDLE_ID="com.local.Arcus"
CONFIG="release"
VERIFY=0
LAUNCH=1
RELEASE_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=1 ;;
    --no-launch) LAUNCH=0 ;;
    --debug) CONFIG="debug" ;;
    --release-build) RELEASE_BUILD=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION="$(tr -d '[:space:]' < VERSION)"
BASE_BUILD="$(tr -d '[:space:]' < BUILD_NUMBER)"
if [[ "$RELEASE_BUILD" == "1" ]]; then BUILD="$BASE_BUILD"; else BUILD="$BASE_BUILD.$(date -u +%y%m%d%H%M)"; fi
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"
LOG="$OUT/last-build.log"
mkdir -p "$OUT"

stop_running() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do pgrep -x "$APP_NAME" >/dev/null 2>&1 || break; sleep 0.2; done
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  fi
}

if [[ "$VERIFY" == "1" ]]; then
  echo "==> Running the complete test suite"
  set +e
  swift test 2>&1 | tee "$OUT/last-test.log" | grep -E "Test run with|✘|error:" | tail -20
  STATUS=${PIPESTATUS[0]}
  set -e
  if [[ $STATUS -ne 0 ]]; then echo "✗ Tests failed (see build/last-test.log)" >&2; exit $STATUS; fi
  echo "✓ Tests passed"
fi

echo "==> Building $APP_NAME $VERSION ($BUILD), $CONFIG"
set +e
swift build -c "$CONFIG" --product "$APP_NAME" > "$LOG" 2>&1
STATUS=$?
set -e
if [[ $STATUS -ne 0 ]]; then
  grep -E "error:" "$LOG" | sort -u | head -40 >&2 || true
  echo "✗ Build failed (see build/last-build.log)" >&2
  exit $STATUS
fi
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
WARNINGS=$( { grep -E "warning:" "$LOG" || true; } | { grep -v "Source files for target" || true; } | sort -u | wc -l | tr -d ' ')
echo "✓ Build succeeded ($WARNINGS warnings)"

echo "==> Staging $APP"
stop_running
STAGE="$OUT/.stage-$$"
rm -rf "$STAGE"
mkdir -p "$STAGE/$APP_NAME.app/Contents/MacOS" "$STAGE/$APP_NAME.app/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$STAGE/$APP_NAME.app/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$ROOT/Arcus/Resources/Info.plist" > "$STAGE/$APP_NAME.app/Contents/Info.plist"
cp "$ROOT/Arcus/Resources/Icon/AppIcon.icns" "$STAGE/$APP_NAME.app/Contents/Resources/AppIcon.icns"
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$STAGE/$APP_NAME.app/Contents/Resources/" \; 2>/dev/null || true
mkdir -p "$STAGE/$APP_NAME.app/Contents/Resources/Docs"
cp "$ROOT"/Docs/*.md "$STAGE/$APP_NAME.app/Contents/Resources/Docs/" 2>/dev/null || true
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/$APP_NAME.app/Contents/Resources/" 2>/dev/null || true
printf 'APPL????' > "$STAGE/$APP_NAME.app/Contents/PkgInfo"
codesign --force --sign - --timestamp=none "$STAGE/$APP_NAME.app" >/dev/null
rm -rf "$APP"
mv "$STAGE/$APP_NAME.app" "$APP"
rm -rf "$STAGE"

echo "==> Validating bundle"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --verify --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == "$BUNDLE_ID" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD" ]]
file "$APP/Contents/MacOS/$APP_NAME" | grep -q "arm64"
if /usr/libexec/PlistBuddy -c 'Print' "$APP/Contents/Info.plist" | grep -E "UsageDescription" >/dev/null; then echo "✗ Unexpected privacy usage description" >&2; exit 1; fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
echo "✓ Bundle valid: $APP ($VERSION, build $BUILD)"

if [[ "$LAUNCH" == "1" ]]; then
  echo "==> Launching"
  /usr/bin/open -n "$APP" --args --skip-onboarding
  PID=""
  for _ in $(seq 1 60); do PID="$(pgrep -x "$APP_NAME" | head -n1 || true)"; [[ -n "$PID" ]] && break; sleep 0.2; done
  if [[ -z "$PID" ]]; then echo "✗ $APP_NAME did not start" >&2; exit 1; fi
  echo "✓ $APP_NAME is running (pid $PID)"
  if [[ "$VERIFY" == "1" ]]; then
    TYPE=""
    for _ in $(seq 1 40); do TYPE="$(lsappinfo info -only ApplicationType -app "$BUNDLE_ID" 2>/dev/null || true)"; [[ "$TYPE" == *Foreground* ]] && break; sleep 0.25; done
    [[ "$TYPE" == *Foreground* ]] || { echo "✗ Not a foreground GUI app ($TYPE)" >&2; exit 1; }
    WINDOWS=0
    for _ in $(seq 1 40); do
      WINDOWS="$(swift "$ROOT/script/count_windows.swift" "$PID" 2>/dev/null || echo 0)"
      [[ "$WINDOWS" -gt 0 ]] && break
      sleep 0.25
    done
    [[ "$WINDOWS" -gt 0 ]] || { echo "✗ No on-screen window" >&2; exit 1; }
    echo "✓ Verified: foreground GUI app with $WINDOWS window(s)"
  fi
fi
