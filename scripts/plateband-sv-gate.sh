#!/usr/bin/env bash
# Validate live Plateband SavedVariables + FElog (agent gate before asking /reload).
set -euo pipefail

OFFLINE=0
[[ "${1:-}" == "--offline" ]] && { OFFLINE=1; shift; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/addons/Plateband/Config.lua"
WANT_VER="$(rg -o 'Config\.VERSION = "([^"]+)"' "$CONFIG" | sed 's/.*"\(.*\)".*/\1/')"
WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"

if [[ "$OFFLINE" -eq 1 ]]; then
  exit 0
fi

SV=""
while IFS= read -r f; do
  [[ -z "$SV" || "$f" -nt "$SV" ]] && SV="$f"
done < <(find "${WOW_ROOT}/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' 2>/dev/null)
[[ -n "$SV" && -f "$SV" ]] || { echo "SV_GATE skip: no Plateband.lua"; exit 2; }

SESSION="$(rg -o 'SESSION_START ver=[0-9.]+' "$SV" | tail -1 | sed 's/.*=//')"
LOAD="$(rg 'PLATES_LOAD ok=1' "$SV" | tail -1 || true)"

if [[ -n "$SESSION" && "$SESSION" != "$WANT_VER" ]]; then
  echo "SV_GATE fail: SESSION_START=$SESSION want disk $WANT_VER (need /reload)"
  exit 1
fi

if [[ -z "$LOAD" && -n "$SESSION" ]]; then
  echo "SV_GATE fail: no PLATES_LOAD ok=1"
  exit 1
fi

FELOG="$(find "${WOW_ROOT}/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null | head -1)"
for f in $(find "${WOW_ROOT}/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null); do
  [[ -z "$FELOG" || "$f" -nt "$FELOG" ]] && FELOG="$f"
done
if [[ -f "$FELOG" ]] && rg -q "200 local variables" "$FELOG" 2>/dev/null; then
  LAST_SESS="$(rg -o 'SESSION_START ver=[0-9.]+' "$SV" | tail -1 || true)"
  if [[ -n "$LAST_SESS" ]]; then
    echo "SV_GATE warn: FElog has 200-local error (confirm after reload $WANT_VER)"
  fi
fi

# Hostile target with TF debuffs should paint (heuristic on last target=yes card)
CARD="$(rg 'PLATEBAND_CARD.*target=yes' "$SV" 2>/dev/null | tail -1 || true)"
if [[ -n "$CARD" ]]; then
  if echo "$CARD" | rg -q 'tf=[1-9]' && echo "$CARD" | rg -q 'painted=0'; then
  if ! echo "$CARD" | rg -q 'friend=1'; then
    echo "SV_GATE fail: hostile target tf>0 but painted=0"
    echo "  $CARD"
    exit 1
  fi
  fi
fi

echo "SV_GATE ok: SESSION=${SESSION:-none} want=$WANT_VER file=$SV"
exit 0