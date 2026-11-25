#!/usr/bin/env bash
# Detect CARD/PAINT regression signatures (harmful merge + friendly WS + sticky).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/plateband-sv-lib.sh
source "$ROOT/scripts/plateband-sv-lib.sh"

pb_sv_context || { echo "WATCH_COVERAGE idle (no SV file)"; exit 0; }

ANOM=0
note() { echo "ANOMALY $1"; ANOM=1; }

echo "WATCH_COVERAGE harmful=CARD.tf+miss,painted+PAINT.harv,miss,painted friendly=PAINT/CARD.friend ws=friend+tf sticky=paint_hold|paint_stale_cleared foreign=harv+miss>1 bleed=punit≠plate tgtSrc PLATES_LOAD+upvalues $(pb_export_session_line)"

LOAD="$(pb_flushed_plates_load "$PB_SV" 2>/dev/null || rg 'PLATES_LOAD ok=1' "$PB_SV" 2>/dev/null | tail -1 || true)"
if [[ -n "${PB_FLUSHED_VER:-}" && pb_ver_sort_ge "${PB_FLUSHED_VER}" "0.2.69" ]]; then
  if ! echo "$LOAD" | rg -q 'PLATES_LOAD ok=1'; then
    note "PLATES_LOAD_missing: session=${PB_FLUSHED_VER} export has no paint start line"
  elif echo "$LOAD" | rg -q 'paint=false'; then
    note "PLATES_LOAD_paint_false: $LOAD"
  fi
fi

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

TGT_CARDS="$(rg 'PLATEBAND_CARD.*target=yes' "$SRC" 2>/dev/null | tail -40 || true)"
FRIEND_CARDS="$(rg 'PLATEBAND_CARD.*friend=1' "$SRC" 2>/dev/null | tail -40 || true)"
ALL_CARDS="$(rg 'PLATEBAND_CARD ver=' "$SRC" 2>/dev/null | tail -80 || true)"
# Full paint tail — short window previously missed Tarantula-class multi-icon bursts.
PAINT_LINES="$(rg 'PAINT ver=' "$SRC" 2>/dev/null | tail -200 || true)"

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
done <<< "$TGT_CARDS"

# Friend WS — never skip friend=1 cards (prior bug short-circuited this).
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if echo "$line" | rg -q 'friend=1' && echo "$line" | rg -q 'painted=0'; then
    if echo "$line" | rg -q 'tf=[1-9]|harv=[1-9]|miss=[1-9]'; then
      if echo "$line" | rg -q 'party=(party|raid)[0-9]'; then
        note "friendly_party_WS_no_paint: $line"
      else
        note "friendly_WS_missing: $line"
      fi
    fi
  fi
done <<< "$FRIEND_CARDS"

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Never match the raw SV ["export"] blob (contains many PAINT substrings).
  echo "$line" | rg -q '^\["export"\]' && continue
  echo "$line" | rg -q 'PAINT ver=' || continue
  # native=0 + nativeVis≥1 + multi-paint (0.2.69+ telemetry)
  if echo "$line" | rg -q 'native=0' && echo "$line" | rg -q 'nativeVis=[1-9]' && echo "$line" | rg -q 'painted=[2-9]'; then
    note "OVERLAP_nativeVis_multi_paint: $line"
  fi
  if echo "$line" | rg -q 'native=0' && echo "$line" | rg -q 'nativeVis=[1-9]' && echo "$line" | rg -q 'miss=[2-9]' && echo "$line" | rg -q 'painted=[2-9]'; then
    note "OVERLAP_parent_on_native_row: $line"
  fi
  # Layout overlap without nativeVis field (0.2.68 and gaps): painted≥2 native=0
  if echo "$line" | rg -q 'native=0' && echo "$line" | rg -q 'painted=[2-9]'; then
    if echo "$line" | rg -q 'friend=1'; then
      note "friend_multi_icon_overlap: $line"
    else
      note "enemy_multi_icon_overlap: $line"
    fi
  fi
  if echo "$line" | rg -q 'friend=1' && echo "$line" | rg -q 'party=(party|raid)[0-9]' && echo "$line" | rg -q 'painted=0'; then
    if echo "$line" | rg -q 'tfRows=[1-9]|miss=[1-9]|harv=[1-9]'; then
      note "friendly_party_WS_no_paint: $line"
    fi
  fi
  echo "$line" | rg -q 'why=paint_stale_cleared|why=paint_hold' && continue
  echo "$line" | rg -q 'why=paint ' || continue
  if echo "$line" | rg -q 'tgtSrc=1' && echo "$line" | rg -q 'tfRows=[2-9]' && echo "$line" | rg -q 'miss=[1-9]' && echo "$line" | rg -q 'painted=0'; then
    if echo "$line" | rg -q 'friend=0'; then
      note "PAINT_foreign_lost: $line"
    fi
  fi
  if echo "$line" | rg -q 'friend=1' && echo "$line" | rg -q 'painted=0' && echo "$line" | rg -q 'tfRows=[1-9]|miss=[1-9]|harv=[1-9]'; then
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
  plate="$(echo "$line" | sed -n 's/.*plate=\([^ ]*\).*/\1/p')"
  punit="$(echo "$line" | sed -n 's/.*punit=\([^ ]*\).*/\1/p')"
  if [[ -n "$plate" && -n "$punit" && "$plate" != "$punit" && "$plate" != "no" && "$punit" != "?" && "$punit" != "no" ]]; then
    note "bleed_plate_ne_punit: plate=$plate punit=$punit $line"
  fi
  if echo "$line" | rg -q 'target=yes' && echo "$line" | rg -q 'painted=[1-9]' && echo "$line" | rg -q 'friend=0'; then
    if [[ -n "$plate" && -n "$punit" && "$plate" != "$punit" && "$plate" != "no" && "$punit" != "?" ]]; then
      if echo "$line" | rg -q 'tgtSrc=0'; then
        note "HELPful_bleed_shield_on_mob?: plate=$plate punit=$punit"
      fi
    fi
  fi
done <<< "$ALL_CARDS"

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