#!/usr/bin/env bash
# Detect CARD/PAINT regression signatures; prints ANOMALY lines (exit 1 if any).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
SV=""
while IFS= read -r f; do
  [[ -z "$SV" || "$f" -nt "$SV" ]] && SV="$f"
done < <(find "${WOW_ROOT}/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' 2>/dev/null)
[[ -f "${SV:-}" ]] || exit 0

ANOM=0
note() { echo "ANOMALY $1"; ANOM=1; }

LAST_CARD="$(rg 'PLATEBAND_CARD' "$SV" 2>/dev/null | tail -1 || true)"
TGT_CARDS="$(rg 'PLATEBAND_CARD.*target=yes' "$SV" 2>/dev/null | tail -8 || true)"

# Hostile target: TF shows debuffs but merge painted none
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line" | rg -q 'friend=1' && continue
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'tf=[1-9]' && echo "$line" | rg -q 'painted=0'; then
    note "hostile_tf_no_paint: $line"
  fi
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'tgtSrc=0' && echo "$line" | rg -q 'tf=[1-9]'; then
    if ! echo "$line" | rg -q 'friend=1'; then
      note "hostile_tgtSrc0_with_tf: $line"
    fi
  fi
  # Party foreign: harv=0 on hostile target while painted=1 only (single own dot)
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'harv=0' && echo "$line" | rg -q 'tf=[2-9]'; then
    note "foreign_skipped_lean_harv: $line"
  fi
  # Friend WS gap
  if echo "$line" | rg -q 'friend=1' && echo "$line" | rg -q 'tf=[1-9]' && echo "$line" | rg -q 'painted=0'; then
    note "friendly_ws_missing: $line"
  fi
done <<< "$TGT_CARDS"

# Bleed: party PW:S era — mob plate painted while target is friendly (friend=0 but punit mismatch)
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'painted=[1-9]' && echo "$line" | rg -q 'friend=0'; then
    plate="$(echo "$line" | sed -n 's/.*plate=\([^ ]*\).*/\1/p')"
    punit="$(echo "$line" | sed -n 's/.*punit=\([^ ]*\).*/\1/p')"
    if [[ -n "$plate" && -n "$punit" && "$plate" != "$punit" && "$plate" != "no" && "$punit" != "?" ]]; then
      if echo "$line" | rg -q 'tgtSrc=0'; then
        note "plate_unit_mismatch_bleed?: plate=$plate punit=$punit"
      fi
    fi
  fi
done <<< "$TGT_CARDS"

# Sticky ghost: hold without later stale clear (weak signal — log paint_hold churn)
HOLDS="$(rg 'paint_hold|paint_stale_cleared' "$SV" 2>/dev/null | tail -6 || true)"
if [[ -n "$HOLDS" ]]; then
  echo "TRACE sticky: $(echo "$HOLDS" | tail -1)"
fi

FELOG="$(find "${WOW_ROOT}/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null | head -1)"
for f in $(find "${WOW_ROOT}/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null); do
  [[ -z "$FELOG" || "$f" -nt "$FELOG" ]] && FELOG="$f"
done
if [[ -f "${FELOG:-}" ]] && rg -q 'Plateband:paint' "$FELOG" 2>/dev/null; then
  ERR="$(rg 'Plateband:paint' "$FELOG" 2>/dev/null | tail -1)"
  note "felog_paint: $ERR"
fi

[[ "$ANOM" -eq 0 ]] && exit 0
exit 1