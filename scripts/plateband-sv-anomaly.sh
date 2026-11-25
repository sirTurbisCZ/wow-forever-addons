#!/usr/bin/env bash
# Detect CARD/PAINT regression signatures (harmful merge + friendly WS + sticky).
# Covers: own DoT, foreign/party DoT, helpful bleed, Weakened Soul (friend=1), sticky prune.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WANT_VER="$(rg -o 'Config\.VERSION = "([^"]+)"' "$ROOT/addons/Plateband/Config.lua" | sed 's/.*"\(.*\)".*/\1/')"
WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
SV=""
while IFS= read -r f; do
  [[ -z "$SV" || "$f" -nt "$SV" ]] && SV="$f"
done < <(find "${WOW_ROOT}/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' 2>/dev/null)
[[ -f "${SV:-}" ]] || { echo "WATCH_COVERAGE idle (no SV file)"; exit 0; }

ANOM=0
note() { echo "ANOMALY $1"; ANOM=1; }

SESSION="$(rg -o 'SESSION_START ver=[0-9.]+' "$SV" 2>/dev/null | tail -1 | sed 's/.*=//' || true)"

echo "WATCH_COVERAGE harmful=CARD.tf+miss,painted+PAINT.harv,miss,painted friendly=PAINT/CARD.friend ws=friend+tf sticky=paint_hold|paint_stale_cleared foreign=harv+miss>1 bleed=punit≠plate tgtSrc session=${SESSION:-?}"

TGT_CARDS="$(rg 'PLATEBAND_CARD.*target=yes' "$SV" 2>/dev/null | tail -12 || true)"
PAINT_LINES="$(rg 'PAINT ver=' "$SV" 2>/dev/null | tail -20 || true)"

# --- CARD: hostile harmful (HARMFUL debuffs on enemy target) ---
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line" | rg -q 'friend=1' && continue
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'tf=[1-9]' && echo "$line" | rg -q 'painted=0'; then
    note "hostile_HARMFUL_no_paint: $line"
  fi
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'tgtSrc=0' && echo "$line" | rg -q 'tf=[1-9]'; then
    note "hostile_tgtSrc0_HARMFUL: $line"
  fi
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'harv=0' && echo "$line" | rg -q 'tf=[2-9]'; then
    note "foreign_PARTY_harv_skipped: $line"
  fi
  if echo "$line" | rg -q 'friend=1' && echo "$line" | rg -q 'tf=[1-9]' && echo "$line" | rg -q 'painted=0'; then
    note "friendly_WS_missing: $line"
  fi
done <<< "$TGT_CARDS"

# --- PAINT traces (per paint pass: miss queue + painted gap count) ---
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if echo "$line" | rg -q 'tgtSrc=1' && echo "$line" | rg -q 'tfRows=[2-9]' && echo "$line" | rg -q 'painted=0'; then
    if echo "$line" | rg -q 'friend=0'; then
      note "PAINT_foreign_lost: $line"
    fi
  fi
  if echo "$line" | rg -q 'friend=1' && echo "$line" | rg -q 'miss=0' && echo "$line" | rg -q 'painted=0' && echo "$line" | rg -q 'tfRows=[1-9]'; then
    note "PAINT_WS_helpful_gap: $line"
  fi
  if echo "$line" | rg -q 'why=paint_stale_cleared'; then
    echo "OK sticky_prune: $line"
  fi
  if echo "$line" | rg -q 'why=paint_hold'; then
    echo "TRACE sticky_hold: $line"
  fi
done <<< "$PAINT_LINES"

# --- HELPful bleed: wrong plate / helpful on hostile ---
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'painted=[1-9]' && echo "$line" | rg -q 'friend=0'; then
    plate="$(echo "$line" | sed -n 's/.*plate=\([^ ]*\).*/\1/p')"
    punit="$(echo "$line" | sed -n 's/.*punit=\([^ ]*\).*/\1/p')"
    if [[ -n "$plate" && -n "$punit" && "$plate" != "$punit" && "$plate" != "no" && "$punit" != "?" ]]; then
      if echo "$line" | rg -q 'tgtSrc=0'; then
        note "HELPful_bleed_shield_on_mob?: plate=$plate punit=$punit"
      fi
    fi
  fi
done <<< "$TGT_CARDS"

FELOG=""
while IFS= read -r f; do
  [[ -z "$FELOG" || "$f" -nt "$FELOG" ]] && FELOG="$f"
done < <(find "${WOW_ROOT}/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null)
if [[ -f "${FELOG:-}" && "$SESSION" == "$WANT_VER" ]] && rg -q 'Plateband:paint' "$FELOG" 2>/dev/null; then
  ERR="$(rg 'Plateband:paint' "$FELOG" 2>/dev/null | tail -1)"
  note "felog_paint_current_session: $ERR"
fi

[[ "$ANOM" -eq 0 ]] && echo "ANOMALY_SCAN ok" && exit 0
exit 1