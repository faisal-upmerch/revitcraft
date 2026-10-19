#!/usr/bin/env bash
# Builds GNU LibreDWG's dwg2dxf for Arcus's DWG read fallback: a self-contained arm64 macOS program (static libredwg,
# no shared libraries, no Python or SWIG bindings, no Homebrew or MacPorts dependencies; only macOS system libraries).
#
#   Tools/LibreDWG/build_libredwg.sh                     build from the cached tarball (never touches the network)
#   Tools/LibreDWG/build_libredwg.sh --download          download the release tarball first if it is not cached
#   Tools/LibreDWG/build_libredwg.sh --tarball <file>    use a tarball you downloaded yourself (checked like a download)
#   Tools/LibreDWG/build_libredwg.sh --force             rebuild even when the cached build is current
#   Tools/LibreDWG/build_libredwg.sh --print-output      print the output folder and exit (used by build_and_run.sh)
#
# The release, its SHA-256 and the mirrors are in libredwg.version. Everything goes to Tools/LibreDWG/cache/ (ignored
# by git): the verified tarball, the build tree and out/ with dwg2dxf, COPYING and the exact source tarball that
# build_and_run.sh copies into Arcus.app (GPLv3 §6: the corresponding source ships next to the program).
#
# LibreDWG is GPLv3+. Arcus only runs dwg2dxf as a separate program and never links it; see THIRD_PARTY_NOTICES.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=libredwg.version
source "$HERE/libredwg.version"
CACHE="$HERE/cache"
OUT="$CACHE/out"
TARBALL="$CACHE/$LIBREDWG_TARBALL"
DOWNLOAD=0
FORCE=0
LOCAL_TARBALL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --download) DOWNLOAD=1 ;;
    --force) FORCE=1 ;;
    --tarball) shift; LOCAL_TARBALL="${1:?--tarball needs a file}" ;;
    --print-output) echo "$OUT"; exit 0 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }
mkdir -p "$CACHE"

# 1. The tarball: cached, given, or (only with --download) fetched.
if [[ -n "$LOCAL_TARBALL" ]]; then
  [[ "$(sha_of "$LOCAL_TARBALL")" == "$LIBREDWG_SHA256" ]] || { echo "✗ $LOCAL_TARBALL does not match LIBREDWG_SHA256 in libredwg.version" >&2; exit 1; }
  cp "$LOCAL_TARBALL" "$TARBALL.tmp" && mv "$TARBALL.tmp" "$TARBALL"
  [[ -f "$LOCAL_TARBALL.sig" ]] && cp "$LOCAL_TARBALL.sig" "$TARBALL.sig"
fi
if [[ ! -f "$TARBALL" ]]; then
  if [[ "$DOWNLOAD" != "1" ]]; then
    echo "✗ $LIBREDWG_TARBALL is not cached. Run Tools/LibreDWG/build_libredwg.sh --download (the only step that uses the network)." >&2
    exit 3
  fi
  for url in $LIBREDWG_URLS; do
    echo "==> Downloading $url"
    if curl -fL --proto '=https' --tlsv1.2 --retry 2 -o "$TARBALL.tmp" "$url"; then
      curl -fsL --proto '=https' --tlsv1.2 -o "$TARBALL.sig.tmp" "$url.sig" && mv "$TARBALL.sig.tmp" "$TARBALL.sig" || true
      mv "$TARBALL.tmp" "$TARBALL"
      break
    fi
  done
  [[ -f "$TARBALL" ]] || { echo "✗ Could not download $LIBREDWG_TARBALL" >&2; exit 1; }
fi
ACTUAL="$(sha_of "$TARBALL")"
if [[ "$ACTUAL" != "$LIBREDWG_SHA256" ]]; then
  echo "✗ $LIBREDWG_TARBALL has SHA-256 $ACTUAL, expected $LIBREDWG_SHA256. Deleted it; nothing was built." >&2
  rm -f "$TARBALL" "$TARBALL.sig"
  exit 1
fi
echo "✓ $LIBREDWG_TARBALL SHA-256 verified"
if command -v gpg >/dev/null 2>&1 && [[ -f "$TARBALL.sig" ]]; then
  if gpg --verify "$TARBALL.sig" "$TARBALL" >/dev/null 2>&1; then echo "✓ GPG signature verified"
  else echo "! GPG signature not verified (import the GNU keyring: https://ftp.gnu.org/gnu/gnu-keyring.gpg); SHA-256 matched"; fi
fi

# 2. Reuse the cached build when the tarball and this script are unchanged.
STAMP="$LIBREDWG_SHA256 $(sha_of "$0")"
if [[ "$FORCE" != "1" && -x "$OUT/dwg2dxf" && -f "$OUT/.stamp" && "$(cat "$OUT/.stamp")" == "$STAMP" ]]; then
  echo "✓ dwg2dxf $LIBREDWG_VERSION is up to date: $OUT/dwg2dxf"
  exit 0
fi

# 3. Build with Xcode's toolchain in a clean environment, so nothing from Homebrew/MacPorts is found or linked.
SRC="$CACHE/build"
rm -rf "$SRC" "$OUT.tmp"
mkdir -p "$SRC" "$OUT.tmp"
tar -xJf "$TARBALL" -C "$SRC"
cd "$SRC/libredwg-$LIBREDWG_VERSION"
CC="$(xcrun -f clang)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS="-arch arm64 -mmacosx-version-min=26.0 -isysroot $SDK -O2"
JOBS="$(sysctl -n hw.ncpu)"
# configure insists on pkg-config but LibreDWG needs no packages: a stand-in that finds nothing keeps every optional
# third-party library (libxml2, PCRE2, ...) out of the build.
SHIM="$SRC/shim"
mkdir -p "$SHIM"
cat > "$SHIM/pkg-config" <<'SH'
#!/bin/sh
case "$1" in --version) echo 0.29.2; exit 0 ;; --atleast-pkgconfig-version) exit 0 ;; esac
exit 1
SH
chmod +x "$SHIM/pkg-config"
echo "==> Configuring LibreDWG $LIBREDWG_VERSION (static, no bindings)"
env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" \
  CC="$CC" CFLAGS="$FLAGS" LDFLAGS="-arch arm64 -mmacosx-version-min=26.0 -isysroot $SDK" PKG_CONFIG="$SHIM/pkg-config" \
  ./configure --prefix="$SRC/prefix" --disable-shared --enable-static --disable-bindings --disable-python \
    --disable-docs --disable-werror --disable-dependency-tracking --without-libiconv-prefix > "$CACHE/configure.log" 2>&1 \
  || { tail -30 "$CACHE/configure.log" >&2; echo "✗ configure failed (see $CACHE/configure.log)" >&2; exit 1; }
echo "==> Building dwg2dxf"
env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" \
  make -j"$JOBS" -C src > "$CACHE/make.log" 2>&1 \
  && env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" \
  make -j"$JOBS" -C programs dwg2dxf >> "$CACHE/make.log" 2>&1 \
  || { tail -30 "$CACHE/make.log" >&2; echo "✗ make failed (see $CACHE/make.log)" >&2; exit 1; }

BIN="programs/dwg2dxf"
[[ -x "$BIN" ]] && file "$BIN" | grep -q "Mach-O 64-bit executable arm64" || { echo "✗ $BIN is not an arm64 executable (libtool wrapper?)" >&2; exit 1; }
# Only macOS system libraries may be linked.
if otool -L "$BIN" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)' ; then
  echo "✗ dwg2dxf links libraries outside macOS (listed above); refusing to bundle it." >&2
  exit 1
fi
cp "$BIN" "$OUT.tmp/dwg2dxf"
strip -x "$OUT.tmp/dwg2dxf"
cp COPYING "$OUT.tmp/COPYING"
cp "$TARBALL" "$OUT.tmp/$LIBREDWG_TARBALL"
[[ -f "$TARBALL.sig" ]] && cp "$TARBALL.sig" "$OUT.tmp/$LIBREDWG_TARBALL.sig"
cat > "$OUT.tmp/SOURCE.txt" <<EOF
GNU LibreDWG $LIBREDWG_VERSION — dwg2dxf, built unmodified from $LIBREDWG_TARBALL
SHA-256 $LIBREDWG_SHA256
Configured: --disable-shared --enable-static --disable-bindings --disable-python --disable-docs (arm64, macOS 26 SDK)
Licence: GNU General Public License v3 or later (COPYING). The complete corresponding source is $LIBREDWG_TARBALL in
this folder; it is also at https://ftp.gnu.org/gnu/libredwg/. Arcus runs dwg2dxf as a separate program and does not
link it.
EOF
echo "$STAMP" > "$OUT.tmp/.stamp"
rm -rf "$OUT"
mv "$OUT.tmp" "$OUT"
cd "$HERE"
rm -rf "$SRC"
echo "✓ Built $OUT/dwg2dxf ($("$OUT/dwg2dxf" --version 2>/dev/null | head -1 || echo "LibreDWG $LIBREDWG_VERSION"))"
