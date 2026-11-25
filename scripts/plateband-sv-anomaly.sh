#!/usr/bin/env bash
# Detect CARD/PAINT regression signatures (harmful merge + friendly WS + sticky).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/plateband-sv-lib.sh
source "$ROOT/scripts/plateband-sv-lib.sh"

pb_sv_context || { echo "WATCH_COVERAGE idle (no SV file)"; exit 0; }

ANOM=0
note() { echo "ANOMALY $1"; ANOM=1; }

echo "WATCH_COVERAGE harmful=CARD.tf+miss,painted+PAINT.harv,miss,painted friendly=PAINT/CARD.friend ws=friend+tf sticky=paint_hold|paint_stale_cleared foreign=harv+miss>1 bleed=punit≠plate tgtSrc $(pb_export_session_line)"

SRC="$(mktemp)"
trap 'rm -f "$SRC"' EXIT
{
  if [[ -f "${PB_AGENT_LOG:-}" ]]; then
    rg '\] PAINT ver=' "$PB_AGENT_LOG" 2>/dev/null || true
    rg 'PLATEBAND_CARD ver=' "$PB_AGENT_LOG" 2>/dev/null || true
  fi
  rg '\] PAINT ver=' "$PB_SV" 2>/dev/null || true
  rg '^\s*"\[[0-9]+\] PAINT ver=' "$PB_SV" 2>/dev/null || true
  rg '^\s*"\[[0-9]+\] PLATEBAND_CARD ver=' "$PB_SV" 2>/dev/null || true
  rg 'PLATEBAND_CARD ver=' "$PB_SV" 2>/dev/null | rg -v '^\["export"\]' || true
  rg '^\["export"\]' "$PB_SV" 2>/dev/null | python3 -c 'import sys,re; s=sys.stdin.read(); s=s.replace("\\n","\n"); [print(x) for x in s.split("\n") if "PAINT ver=" in x or "PLATEBAND_CARD ver=" in x]' 2>/dev/null || true
} > "$SRC"

TGT_CARDS="$(rg 'PLATEBAND_CARD.*target=yes' "$SRC" 2>/dev/null | tail -12 || true)"
PAINT_LINES="$(rg 'PAINT ver=' "$SRC" 2>/dev/null | tail -20 || true)"

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

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line" | rg -q 'why=paint_stale_cleared|why=paint_hold' && continue
  echo "$line" | rg -q 'why=paint ' || continue
  if echo "$line" | rg -q 'tgtSrc=1' && echo "$line" | rg -q 'tfRows=[2-9]' && echo "$line" | rg -q 'miss=[1-9]' && echo "$line" | rg -q 'painted=0'; then
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

SESSION_CARDS="$(rg 'PLATEBAND_CARD ver=' "$SRC" 2>/dev/null | tail -200 || true)"
if echo "$SESSION_CARDS" | rg -q '.'; then
  SEEN_LAST="$(echo "$SESSION_CARDS" | tail -1 | sed -n 's/.*seen=\([0-9]*\).*/\1/p')"
  CARD_N="$(echo "$SESSION_CARDS" | rg -c '.' 2>/dev/null || echo 0)"
  if [[ -n "${SEEN_LAST:-}" && "$SEEN_LAST" -gt 20 && "${CARD_N:-0}" -ge 8 ]]; then
  CARD_TAIL="$(echo "$SESSION_CARDS" | tail -25)"
    PAINT_ANY="$(rg 'PAINT ver=' "$SRC" 2>/dev/null | rg 'painted=[1-9]' | head -1 || true)"
    if ! echo "$SESSION_CARDS" | rg -q 'painted=[1-9]' && [[ -z "$PAINT_ANY" ]]; then
      note "session_zero_paint_streak: seen=$SEEN_LAST cards=$CARD_N"
    elif [[ $(echo "$CARD_TAIL" | wc -l | tr -d ' ') -ge 12 ]] && ! echo "$CARD_TAIL" | rg -q 'painted=[1-9]'; then
      note "session_paint_tail_streak: seen=$SEEN_LAST tail_cards=25"
    fi
  fi
fi

FELOG=""
while IFS= read -r f; do
  [[ -z "$FELOG" || "$f" -nt "$FELOG" ]] && FELOG="$f"
done < <(find "$(pb_wow_root)/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null)
LOAD_OK="$(rg 'PLATES_LOAD ok=1.*paint=true' "$PB_SV" 2>/dev/null | tail -1 || true)"
if [[ -z "$LOAD_OK" && -f "${SRC:-}" ]]; then
  LOAD_OK="$(rg 'PLATES_LOAD ok=1.*paint=true' "$SRC" 2>/dev/null | tail -1 || true)"
fi
if [[ -f "${FELOG:-}" ]] && rg -q 'ADDON_ACTION_BLOCKED.*Plateband.*SetPoint' "$FELOG" 2>/dev/null; then
  ERR="$(rg 'ADDON_ACTION_BLOCKED.*Plateband' "$FELOG" 2>/dev/null | tail -1)"
  note "felog_taint: $ERR"
fi
if [[ -f "${FELOG:-}" ]] && [[ -z "$LOAD_OK" ]] && rg -q 'Plateband:paint.*nil value' "$FELOG" 2>/dev/null; then
  note "felog_paint_nil: PLATES_LOAD paint!=true — Plates.lua may not have loaded"
elif [[ -f "${FELOG:-}" ]] && rg -q 'Plateband:paint.*nil value' "$FELOG" 2>/dev/null; then
  echo "FELOG note: paint nil present but PLATES_LOAD paint=true (historical pre-reload unless acFail=1)"
fi
PAINT_N="$(rg "PAINT ver=${PB_LIVE_VER} " "$SRC" 2>/dev/null | wc -l | tr -d ' ')"
if echo "$TGT_CARDS" | rg -q 'painted=[1-9]' && [[ "${PAINT_N:-0}" -eq 0 ]]; then
  note "PAINT_lines_missing: cards show painted>0 but no PAINT in log (paintTraceOn regression?)"
fi

if [[ "$ANOM" -eq 0 ]]; then
  echo "ANOMALY_SCAN ok (live_ver=$PB_LIVE_VER client_ver=${PB_CLIENT_VER:-?} deployed_ver=${PB_RUNTIME_VER} reload_pending=${PB_RELOAD_PENDING:-no})"
  exit 0
fi
exit 1