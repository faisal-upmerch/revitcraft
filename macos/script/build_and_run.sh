#!/usr/bin/env bash
# Builds Arcus, stages build/Arcus.app, signs and validates it, installs it to /Applications and launches it from there.
#
#   script/build_and_run.sh               release build, stage, sign, validate, install, launch
#   script/build_and_run.sh --verify      clean-ish verify: run all tests, build, validate, install, launch, confirm a GUI window
#   script/build_and_run.sh --no-launch   build, stage and install only
#   script/build_and_run.sh --no-install  leave the build in build/Arcus.app (launches from there)
#   script/build_and_run.sh --debug       debug configuration
#   script/build_and_run.sh --release-build  use BUILD_NUMBER exactly (used by release_local.sh)
#
# Signing: ARCUS_SIGN_IDENTITY (a name or SHA-1 from `security find-identity -v -p codesigning`) if set, otherwise the
# first "Apple Development" identity in the keychain, otherwise ad hoc. A stable certificate keeps the app's designated
# requirement the same from build to build, so macOS privacy grants (Accessibility, Screen Recording) survive rebuilds.
#
# DWG engines (Docs/DWGSDKSetup.md): Arcus.app/Contents/Helpers gets arcus-dwg (Rust, acadrust; built with
# ~/.cargo/bin/cargo, offline from Cargo.lock) and LibreDWG's dwg2dxf (from Tools/LibreDWG/cache, made by
# Tools/LibreDWG/build_libredwg.sh). Both are rebuilt only when their inputs change. If one can't be built the app still
# builds, with a warning, and DWG falls back to a converter the user installed.
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
INSTALL=1
INSTALL_DIR="${ARCUS_INSTALL_DIR:-/Applications}"
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=1 ;;
    --no-launch) LAUNCH=0 ;;
    --no-install) INSTALL=0 ;;
    --debug) CONFIG="debug" ;;
    --release-build) RELEASE_BUILD=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
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

# DWG: the bundled DWG engines.
DWG_HELPERS=()
DWG_WARNINGS=()
CARGO="${CARGO:-$HOME/.cargo/bin/cargo}"
ACADRUST_BIN="$ROOT/Tools/DWGHelper/target/release/arcus-dwg"
if [[ -x "$CARGO" ]] || command -v cargo >/dev/null 2>&1; then
  [[ -x "$CARGO" ]] || CARGO="$(command -v cargo)"
  echo "==> Building the DWG engine (arcus-dwg, acadrust)"
  if (cd "$ROOT/Tools/DWGHelper" && PATH="$(dirname "$CARGO"):$PATH" "$CARGO" build --release --locked --offline) > "$OUT/last-dwg-helper.log" 2>&1; then
    DWG_HELPERS+=("$ACADRUST_BIN")
    echo "✓ arcus-dwg ready"
  else
    DWG_WARNINGS+=("arcus-dwg did not build (see build/last-dwg-helper.log; run 'cargo fetch --locked' in Tools/DWGHelper once if crates are missing)")
  fi
else
  DWG_WARNINGS+=("Rust is not installed, so arcus-dwg was not built (install rustup, then rebuild)")
fi
LIBREDWG_OUT="$("$ROOT/Tools/LibreDWG/build_libredwg.sh" --print-output)"
echo "==> Building LibreDWG dwg2dxf (cached)"
if "$ROOT/Tools/LibreDWG/build_libredwg.sh" > "$OUT/last-libredwg.log" 2>&1; then
  DWG_HELPERS+=("$LIBREDWG_OUT/dwg2dxf")
  echo "✓ dwg2dxf ready"
else
  DWG_WARNINGS+=("LibreDWG dwg2dxf is not bundled ($(tail -1 "$OUT/last-libredwg.log"))")
fi

echo "==> Staging $APP"
stop_running
STAGE="$OUT/.stage-$$"
rm -rf "$STAGE"
mkdir -p "$STAGE/$APP_NAME.app/Contents/MacOS" "$STAGE/$APP_NAME.app/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$STAGE/$APP_NAME.app/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$ROOT/Arcus/Resources/Info.plist" > "$STAGE/$APP_NAME.app/Contents/Info.plist"
cp "$ROOT/Arcus/Resources/Icon/AppIcon.icns" "$STAGE/$APP_NAME.app/Contents/Resources/AppIcon.icns"
# FM3: document icons for .arcus, .arcusfamily and .arcusfurniture, drawn by the bench tool.
swift build -c "$CONFIG" --product arcus-bench >> "$LOG" 2>&1
"$BIN_DIR/arcus-bench" --document-icons "$STAGE/$APP_NAME.app/Contents/Resources" >/dev/null
# FM9: the Furniture Library (every registered piece, thumbnails and index.json), built by the bench tool.
"$BIN_DIR/arcus-bench" --furniture-library "$STAGE/$APP_NAME.app/Contents/Resources/Furniture Library" \
  --app-version "$VERSION" --app-build "$BUILD" >> "$LOG" 2>&1 || { echo "✗ Furniture Library build failed (see $LOG)"; exit 1; }
echo "✓ Furniture Library: $(find "$STAGE/$APP_NAME.app/Contents/Resources/Furniture Library" -name '*.arcusfurniture' -maxdepth 2 | wc -l | tr -d ' ') pieces"
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$STAGE/$APP_NAME.app/Contents/Resources/" \; 2>/dev/null || true
mkdir -p "$STAGE/$APP_NAME.app/Contents/Resources/Docs"
cp "$ROOT"/Docs/*.md "$STAGE/$APP_NAME.app/Contents/Resources/Docs/" 2>/dev/null || true
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/$APP_NAME.app/Contents/Resources/" 2>/dev/null || true
printf 'APPL????' > "$STAGE/$APP_NAME.app/Contents/PkgInfo"
# DWG: helpers and their licences. LibreDWG ships with its exact source tarball and COPYING (GPLv3 §6).
if [[ ${#DWG_HELPERS[@]} -gt 0 ]]; then
  mkdir -p "$STAGE/$APP_NAME.app/Contents/Helpers"
  for h in "${DWG_HELPERS[@]}"; do cp "$h" "$STAGE/$APP_NAME.app/Contents/Helpers/"; done
fi
TP="$STAGE/$APP_NAME.app/Contents/Resources/ThirdParty"
if [[ -x "$STAGE/$APP_NAME.app/Contents/Helpers/arcus-dwg" ]]; then
  mkdir -p "$TP/acadrust"
  cp "$ROOT/Tools/DWGHelper/THIRD_PARTY_LICENSES.txt" "$TP/acadrust/"
fi
if [[ -x "$STAGE/$APP_NAME.app/Contents/Helpers/dwg2dxf" ]]; then
  mkdir -p "$TP/LibreDWG"
  cp "$LIBREDWG_OUT"/COPYING "$LIBREDWG_OUT"/SOURCE.txt "$LIBREDWG_OUT"/libredwg-*.tar.xz "$TP/LibreDWG/"
  cp "$LIBREDWG_OUT"/libredwg-*.tar.xz.sig "$TP/LibreDWG/" 2>/dev/null || true
fi
SIGN_IDENTITY="${ARCUS_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: /{print $2; exit}')"
fi
# Inside-out: the helpers first, then the app (no --deep). Hardened runtime is not used.
for h in "$STAGE/$APP_NAME.app/Contents/Helpers/"*; do
  [[ -f "$h" ]] || continue
  codesign --force --sign "${SIGN_IDENTITY:--}" --timestamp=none "$h" >/dev/null
done
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$STAGE/$APP_NAME.app" >/dev/null
  SIGNED_BY="$(codesign -dv --verbose=2 "$STAGE/$APP_NAME.app" 2>&1 | sed -n 's/^Authority=//p' | head -n1)"
else
  codesign --force --sign - --timestamp=none "$STAGE/$APP_NAME.app" >/dev/null
  SIGNED_BY="ad hoc (no Apple Development identity found)"
fi
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
for h in "$APP/Contents/Helpers/"*; do
  [[ -f "$h" ]] || continue
  codesign --verify --strict "$h"
  file "$h" | grep -q "arm64"
  if otool -L "$h" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)' >/dev/null; then echo "✗ $(basename "$h") links non-system libraries" >&2; exit 1; fi
done
if [[ -x "$APP/Contents/Helpers/arcus-dwg" ]]; then "$APP/Contents/Helpers/arcus-dwg" version >/dev/null || { echo "✗ arcus-dwg does not run" >&2; exit 1; }; fi
if [[ -x "$APP/Contents/Helpers/dwg2dxf" ]]; then
  [[ -f "$APP/Contents/Resources/ThirdParty/LibreDWG/COPYING" ]] && ls "$APP/Contents/Resources/ThirdParty/LibreDWG/"libredwg-*.tar.xz >/dev/null \
    || { echo "✗ dwg2dxf is bundled without its GPL source tarball and COPYING" >&2; exit 1; }
fi
echo "✓ Bundle valid: $APP ($VERSION, build $BUILD), signed by $SIGNED_BY"
if [[ ${#DWG_WARNINGS[@]} -gt 0 ]]; then
  for w in "${DWG_WARNINGS[@]}"; do echo "⚠ DWG: $w. DWG import falls back to a converter the user installed; DWG export is unavailable without arcus-dwg." >&2; done
else
  echo "✓ DWG engines bundled: $(ls "$APP/Contents/Helpers" | tr '\n' ' ')"
fi

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
RUN_APP="$APP"
if [[ "$INSTALL" == "1" ]]; then
  echo "==> Installing to $INSTALL_DIR"
  INSTALLED="$INSTALL_DIR/$APP_NAME.app"
  # Never leave a half-copied app in place (macOS reports a bundle opened mid-copy as "damaged"): copy beside it, check
  # the copy's signature, then swap it in with two renames and only then delete the old one.
  rm -rf "$INSTALLED.new" "$INSTALLED.old"
  ditto "$APP" "$INSTALLED.new"
  codesign --verify --strict "$INSTALLED.new"
  [[ -e "$INSTALLED" ]] && mv "$INSTALLED" "$INSTALLED.old"
  mv "$INSTALLED.new" "$INSTALLED"
  rm -rf "$INSTALLED.old"
  codesign --verify --strict "$INSTALLED"
  # Only the installed copy is registered, so Finder, Spotlight and `open -b` find the one in Applications.
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
  RUN_APP="$INSTALLED"
  echo "✓ Installed: $INSTALLED"
else
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi

if [[ "$LAUNCH" == "1" ]]; then
  echo "==> Launching"
  /usr/bin/open -n "$RUN_APP" --args --skip-onboarding
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
