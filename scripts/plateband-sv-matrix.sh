#!/usr/bin/env bash
# Multi-scenario SV matrix (agent); exit 0 when all observed signals pass.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WANT_VER="$(rg -o 'Config\.VERSION = "([^"]+)"' "$ROOT/addons/Plateband/Config.lua" | sed 's/.*"\(.*\)".*/\1/')"
WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
SV=""
while IFS= read -r f; do
  [[ -z "$SV" || "$f" -nt "$SV" ]] && SV="$f"
done < <(find "${WOW_ROOT}/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' 2>/dev/null)
[[ -f "${SV:-}" ]] || { echo "MATRIX fail: no SV"; exit 1; }

SESSION="$(rg -o 'SESSION_START ver=[0-9.]+' "$SV" | tail -1 | sed 's/.*=//')"
[[ "$SESSION" == "$WANT_VER" ]] || { echo "MATRIX fail: session=$SESSION want=$WANT_VER"; exit 1; }

rg -q 'PLATES_LOAD ok=1' "$SV" || { echo "MATRIX fail: PLATES_LOAD"; exit 1; }

fail=0
check() { echo "  $1: $2"; [[ "$2" == "OK" ]] || fail=1; }

# Own DoTs: any target=yes hostile painted>0 or harv>0
HOSTILE="$(rg 'PLATEBAND_CARD.*target=yes' "$SV" | rg -v 'friend=1' | tail -5 || true)"
if echo "$HOSTILE" | rg -q 'painted=[1-9]'; then
  check "own_foreign_paint" "OK"
else
  check "own_foreign_paint" "MISSING (no hostile target=yes painted>0 yet)"
fi

if echo "$HOSTILE" | rg -q 'tgtSrc=1.*painted=[1-9]'; then
  check "tgt_bind" "OK"
else
  check "tgt_bind" "WAIT"
fi

FRIEND="$(rg 'PLATEBAND_CARD.*friend=1' "$SV" | tail -3 || true)"
if [[ -n "$FRIEND" ]]; then
  if echo "$FRIEND" | rg -q 'painted=[1-9]'; then
    check "friendly_ws" "OK"
  else
    check "friendly_ws" "MISSING"
    fail=1
  fi
else
  check "friendly_ws" "WAIT (no friend=1 card)"
fi

if rg -q 'paint_stale_cleared' "$SV" 2>/dev/null; then
  check "prune_stale" "OK"
else
  check "prune_stale" "WAIT (no expire repro in SV)"
fi

[[ "$fail" -eq 0 ]] && echo "MATRIX pass (version $SESSION)" && exit 0
echo "MATRIX incomplete or fail — keep watching"
exit 1