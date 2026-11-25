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

SRC="$PB_SV"
if [[ -f "${PB_AGENT_LOG:-}" ]]; then
  SRC="$(mktemp)"
  {
    rg 'PLATEBAND_CARD|PAINT ' "$PB_AGENT_LOG" 2>/dev/null || true
    rg 'PLATEBAND_CARD|PAINT ' "$PB_SV" 2>/dev/null || true
  } > "$SRC"
fi

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

SESSION_CARDS="$(rg 'PLATEBAND_CARD' "$SRC" 2>/dev/null | tail -200 || true)"
if echo "$SESSION_CARDS" | rg -q '.'; then
  SEEN_LAST="$(echo "$SESSION_CARDS" | tail -1 | sed -n 's/.*seen=\([0-9]*\).*/\1/p')"
  if [[ -n "${SEEN_LAST:-}" && "$SEEN_LAST" -gt 20 ]]; then
    if ! echo "$SESSION_CARDS" | rg -q 'painted=[1-9]'; then
      note "session_zero_paint_streak: seen=$SEEN_LAST cards=$(echo "$SESSION_CARDS" | wc -l | tr -d ' ')"
    fi
  fi
fi

FELOG=""
while IFS= read -r f; do
  [[ -z "$FELOG" || "$f" -nt "$FELOG" ]] && FELOG="$f"
done < <(find "$(pb_wow_root)/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null)
if [[ -f "${FELOG:-}" ]] && rg -q 'ADDON_ACTION_BLOCKED.*Plateband.*SetPoint' "$FELOG" 2>/dev/null; then
  ERR="$(rg 'ADDON_ACTION_BLOCKED.*Plateband' "$FELOG" 2>/dev/null | tail -1)"
  note "felog_taint: $ERR"
fi

if [[ "$ANOM" -eq 0 ]]; then
  echo "ANOMALY_SCAN ok (live_ver=$PB_LIVE_VER client_ver=${PB_CLIENT_VER:-?} deployed_ver=${PB_RUNTIME_VER} reload_pending=${PB_RELOAD_PENDING:-no})"
  exit 0
fi
exit 1