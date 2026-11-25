#!/usr/bin/env bash
# Read Plateband silent PAINT trace from SavedVariables (agent / dev).
set -euo pipefail

WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
WOW_ROOT="${WOW_ROOT%/}"
SV_GLOB="${WOW_ROOT}/WTF/Account/*/SavedVariables/Plateband.lua"

shopt -s nullglob
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find "${WOW_ROOT}/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' -print0 2>/dev/null)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No Plateband.lua found under: $SV_GLOB" >&2
  exit 1
fi

# Newest mtime wins (multi-account).
pick="${files[0]}"
for f in "${files[@]}"; do
  if [[ "$f" -nt "$pick" ]]; then
    pick="$f"
  fi
done

echo "=== $pick ==="
echo "--- PAINT / SESSION (tail) ---"
rg -n "PAINT |PLATE |PLATEBAND_CARD|SESSION_START" "$pick" 2>/dev/null | tail -n "${1:-40}" || \
  grep -E "PAINT |PLATE |PLATEBAND_CARD|SESSION_START" "$pick" | tail -n "${1:-40}"