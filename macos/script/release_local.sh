#!/usr/bin/env bash
# Local release: bumps VERSION (patch|minor|major) and BUILD_NUMBER atomically, records release notes,
# builds the release app with the exact build number and verifies it. No remote, no signing identity, no upload.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
KIND="${1:-patch}"
[[ "$KIND" =~ ^(patch|minor|major)$ ]] || { echo "usage: $0 patch|minor|major" >&2; exit 2; }
OLD_VERSION="$(tr -d '[:space:]' < VERSION)"
OLD_BUILD="$(tr -d '[:space:]' < BUILD_NUMBER)"
IFS=. read -r MA MI PA <<< "$OLD_VERSION"
case "$KIND" in
  major) MA=$((MA + 1)); MI=0; PA=0 ;;
  minor) MI=$((MI + 1)); PA=0 ;;
  patch) PA=$((PA + 1)) ;;
esac
NEW_VERSION="$MA.$MI.$PA"
NEW_BUILD=$((OLD_BUILD + 1))
BACKUP="$(mktemp -d)"
cp VERSION BUILD_NUMBER "$BACKUP/"
[[ -f RELEASE_NOTES.md ]] && cp RELEASE_NOTES.md "$BACKUP/"
restore() { cp "$BACKUP/VERSION" "$BACKUP/BUILD_NUMBER" .; [[ -f "$BACKUP/RELEASE_NOTES.md" ]] && cp "$BACKUP/RELEASE_NOTES.md" . || true; echo "✗ Release aborted; version files restored." >&2; }
trap restore ERR
TMP="$(mktemp -d)"
echo "$NEW_VERSION" > "$TMP/VERSION"
echo "$NEW_BUILD" > "$TMP/BUILD_NUMBER"
{ echo "## $NEW_VERSION (build $NEW_BUILD) — $(date -u +%Y-%m-%d)"; echo; echo "- Local $KIND release."; echo; [[ -f RELEASE_NOTES.md ]] && cat RELEASE_NOTES.md; } > "$TMP/RELEASE_NOTES.md"
mv "$TMP/VERSION" VERSION; mv "$TMP/BUILD_NUMBER" BUILD_NUMBER; mv "$TMP/RELEASE_NOTES.md" RELEASE_NOTES.md
echo "==> Releasing $NEW_VERSION ($NEW_BUILD)"
"$ROOT/script/build_and_run.sh" --verify --release-build
if git -C "$ROOT" rev-parse >/dev/null 2>&1; then
  git -C "$ROOT" add VERSION BUILD_NUMBER RELEASE_NOTES.md
  git -C "$ROOT" commit -q -m "Release $NEW_VERSION ($NEW_BUILD)" && git -C "$ROOT" tag -f "v$NEW_VERSION" >/dev/null
fi
trap - ERR
echo "✓ Released Arcus $NEW_VERSION build $NEW_BUILD → build/Arcus.app"
