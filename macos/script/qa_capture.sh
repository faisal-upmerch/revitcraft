#!/usr/bin/env bash
# Runs Arcus's in-app QA harness and captures each announced window state with screencapture.
#   script/qa_capture.sh <scenario: workflow|screenshots|all> <output-dir>
# screencapture needs Screen Recording permission for the terminal running this script (not for Arcus).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENARIO="${1:-all}"; OUT="${2:-$ROOT/build/qa}"
mkdir -p "$OUT/screenshots"
pkill -x Arcus >/dev/null 2>&1 || true
sleep 0.5
"$ROOT/build/Arcus.app/Contents/MacOS/Arcus" --skip-onboarding --no-hub --qa "$SCENARIO" --qa-out "$OUT" --qa-quit 2>"$OUT/stderr.log" | while IFS= read -r line; do
  echo "$line" >> "$OUT/stdout.log"
  if [[ "$line" == QA-CAPTURE* ]]; then
    read -r _ wid name <<< "$line"
    screencapture -x -o -l"$wid" "$OUT/screenshots/$name.png" 2>/dev/null || true
  fi
done
if [[ -f "$OUT/results.json" ]]; then
  /usr/bin/plutil -convert json -o - "$OUT/results.json" >/dev/null 2>&1 || true
  grep -E '"(passed|failed)"' "$OUT/results.json" | head -2
fi
