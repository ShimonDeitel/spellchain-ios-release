#!/usr/bin/env bash
#
# setup_words.sh — build/setup step that bundles the offline dictionary.
#
# Copies macOS /usr/share/dict/words, filtered to lowercase a–z words of length 3–7, into the app
# bundle as Spellchain/Resources/words.txt. The app loads this file at launch into a Set<String>
# for O(1) word validation (see WordDictionary.swift).
#
# Run from the iOS/ directory:  ./scripts/setup_words.sh
# Idempotent: regenerates words.txt each time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"
SRC="/usr/share/dict/words"
OUT_DIR="$IOS_DIR/Spellchain/Resources"
OUT="$OUT_DIR/words.txt"

if [[ ! -f "$SRC" ]]; then
  echo "error: $SRC not found (macOS word list). Cannot build dictionary." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# lowercase a–z only, length 3–7, deduped + sorted.
LC_ALL=C grep -E '^[A-Za-z]{3,7}$' "$SRC" \
  | tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C sort -u > "$OUT"

echo "Wrote $(wc -l < "$OUT" | tr -d ' ') words to $OUT ($(du -h "$OUT" | cut -f1))"
