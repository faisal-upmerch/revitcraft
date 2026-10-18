#!/usr/bin/env bash
# Verifies local prerequisites for building Arcus. Installs nothing; uses only Apple toolchain components.
set -euo pipefail
fail() { echo "✗ $1" >&2; exit 1; }
command -v swift >/dev/null || fail "Swift not found. Install Xcode 26 or newer and run: xcode-select -s /Applications/Xcode.app"
SWIFT_VER="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p' | head -1)"
MAJOR="${SWIFT_VER%%.*}"; MINOR="$(echo "$SWIFT_VER" | cut -d. -f2)"
{ [[ "$MAJOR" -gt 6 ]] || { [[ "$MAJOR" -eq 6 ]] && [[ "$MINOR" -ge 2 ]]; }; } || fail "Swift 6.2+ required (found $SWIFT_VER)."
OS="$(sw_vers -productVersion)"; [[ "${OS%%.*}" -ge 26 ]] || fail "macOS 26 or newer required (found $OS)."
[[ "$(uname -m)" == "arm64" ]] || echo "! Arcus targets Apple silicon; building on $(uname -m) is untested."
for t in codesign iconutil plutil xcrun; do command -v $t >/dev/null || fail "$t not found (Xcode command line tools)."; done
xcrun --find metal >/dev/null 2>&1 || echo "• Metal shaders are compiled at runtime; no offline metal toolchain needed."
if [[ -n "${ARCUS_ODA_SDK_DIR:-}" ]]; then echo "• DWG: using ODA Drawings SDK at $ARCUS_ODA_SDK_DIR"; else echo "• DWG: ODA Drawings SDK not configured; DWG import will be reported as unavailable (see Docs/DWGSDKSetup.md)."; fi
echo "✓ Toolchain OK: Swift $SWIFT_VER, macOS $OS"
