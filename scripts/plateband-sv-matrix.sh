#!/usr/bin/env bash
# Multi-scenario paint matrix — gated on live_ver (0.2.51+), not flushed SESSION alone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/plateband-sv-lib.sh
source "$ROOT/scripts/plateband-sv-lib.sh"

if ! pb_sv_context; then
  echo "MATRIX skip: no SV"
  exit 1
fi

if ! pb_live_ver_ok "$PB_LIVE_VER" "$PB_DISK_VER"; then
  echo "MATRIX fail: live_ver=$PB_LIVE_VER need>=${PB_MIN_LIVE_VER:-0.2.51} flushed=$PB_FLUSHED_VER runtime=$PB_RUNTIME_VER"
  exit 1
fi

if [[ "$PB_FLUSH_LAG" != "yes" ]]; then
  LOAD="$(rg 'PLATES_LOAD ok=1' "$PB_SV" 2>/dev/null | tail -1 || true)"
  if [[ -z "$LOAD" ]]; then
    echo "MATRIX fail: PLATES_LOAD missing (paint chunk likely failed — check FElog 60 upvalues)"
    exit 1
  fi
  if echo "$LOAD" | rg -q 'paint=false'; then
    echo "MATRIX fail: PLATES_LOAD paint=false"
    echo "  $LOAD"
    exit 1
  fi
fi

fail=0
check() {
  if [[ "$2" == WAIT* && "${PB_RELOAD_PENDING:-no}" == yes ]]; then
    echo "  $1: $2 (reload_pending — playbook only)"
    return
  fi
  echo "  $1: $2"
  [[ "$2" == "OK" ]] || fail=1
}

SV_DATA="$PB_SV"
if [[ -f "${PB_AGENT_LOG:-}" ]]; then
  SV_DATA="${PB_AGENT_LOG}.with-sv"
  {
    grep 'PLATEBAND_CARD' "$PB_AGENT_LOG" 2>/dev/null || true
    rg 'PLATEBAND_CARD' "$PB_SV" 2>/dev/null || true
  } > "$SV_DATA"
else
  SV_DATA="$PB_SV"
fi

HOSTILE="$(rg 'PLATEBAND_CARD.*target=yes' "$SV_DATA" 2>/dev/null | rg -v 'friend=1' | tail -8 || true)"
HOSTILE_RECENT="$(echo "$HOSTILE" | tail -3)"
if echo "$HOSTILE_RECENT" | rg -q 'tgtSrc=1.*painted=[1-9]'; then
  check "own_foreign_paint" "OK"
elif echo "$HOSTILE" | rg -q 'painted=[1-9]'; then
  check "own_foreign_paint" "STALE (painted>0 but recent tgtSrc0?)"
  fail=1
else
  check "own_foreign_paint" "WAIT (no hostile target=yes painted>0 in data)"
fi

TGT_PAINT="$(rg 'PAINT ver=' "$SV_DATA" 2>/dev/null | rg 'tgt=1.*tgtSrc=1.*painted=[1-9]' | tail -3 || true)"
if [[ -n "$TGT_PAINT" ]]; then
  check "tgt_bind" "OK"
elif echo "$HOSTILE_RECENT" | rg -q 'target=yes.*tf=[1-9]'; then
  FRIEND_TGT_PAINT="$(rg 'PAINT ver=' "$SV_DATA" 2>/dev/null | rg 'friend=1.*tgtSrc=1.*painted=[1-9]' | tail -1 || true)"
  if [[ -n "$FRIEND_TGT_PAINT" ]]; then
    check "tgt_bind" "OK (friend tgt paint)"
  else
    check "tgt_bind" "FAIL (target=yes tf>0, no tgtSrc PAINT)"
    fail=1
  fi
else
  check "tgt_bind" "WAIT"
fi

PAINT_FRIEND_WS="$(rg 'PAINT ver=.*friend=1' "$SV_DATA" 2>/dev/null | rg 'tfRows=[1-9].*painted=[1-9]' | tail -5 || true)"
FRIEND="$(rg 'PLATEBAND_CARD.*friend=1' "$SV_DATA" 2>/dev/null | tail -8 || true)"
FRIEND_TF="$(echo "$FRIEND" | rg 'friend=1.*tf=[1-9]' | tail -3 || true)"
FRIEND_LAST="$(echo "$FRIEND" | tail -1)"
if [[ -n "$PAINT_FRIEND_WS" ]] && echo "$PAINT_FRIEND_WS" | tail -2 | rg -q 'painted=[1-9]'; then
  check "friendly_ws" "OK (PAINT friend tfRows)"
elif [[ -n "$FRIEND_TF" ]]; then
  if echo "$FRIEND_TF" | rg -q 'painted=0'; then
    if echo "$FRIEND_LAST" | rg -q 'friend=1.*tf=[1-9].*painted=0'; then
      check "friendly_ws" "MISSING (recent tf>0 painted=0)"
      fail=1
    elif echo "$FRIEND_TF" | tail -1 | rg -q 'painted=[1-9]'; then
      check "friendly_ws" "FLAKY (tf>0 streak with gaps)"
      fail=1
    else
      check "friendly_ws" "MISSING"
      fail=1
    fi
  elif echo "$FRIEND_LAST" | rg -q 'friend=1.*painted=[1-9]'; then
    check "friendly_ws" "OK"
  else
    check "friendly_ws" "WAIT (friend tf, no recent paint)"
  fi
elif [[ -n "$FRIEND" ]]; then
  check "friendly_ws" "WAIT (friend plate, no TF debuff yet)"
else
  check "friendly_ws" "WAIT (no friend=1 card)"
fi

PAINT_FRIEND_RECENT="$(rg 'PAINT ver=.*friend=1' "$SV_DATA" 2>/dev/null | tail -12 || true)"
PAINT_FRIEND_TF="$(echo "$PAINT_FRIEND_RECENT" | rg 'tfRows=[1-9]' | tail -5 || true)"
if [[ -n "$PAINT_FRIEND_TF" ]]; then
  if echo "$PAINT_FRIEND_TF" | tail -2 | rg -q 'painted=0'; then
    check "friendly_ws_paint" "MISSING (recent friend tf, painted=0)"
    fail=1
  elif echo "$PAINT_FRIEND_TF" | rg -q 'painted=[1-9]'; then
    check "friendly_ws_paint" "OK"
  else
    check "friendly_ws_paint" "WAIT"
  fi
elif rg -q 'PAINT ver=.*friend=1.*painted=[1-9]' "$SV_DATA" 2>/dev/null; then
  check "friendly_ws_paint" "OK (stale tail)"
else
  check "friendly_ws_paint" "WAIT"
fi
OVERLAP_HOSTILE="$(rg 'PAINT ver=' "$SV_DATA" 2>/dev/null | rg 'friend=0' | rg 'native=0' | rg 'painted=[2-9]' | rg 'miss=[2-9]' | tail -5 || true)"
OVERLAP_ANY="$(rg 'PAINT ver=' "$SV_DATA" 2>/dev/null | rg 'native=0.*nativeVis=[1-9]' | rg 'painted=[2-9]' | tail -5 || true)"
if [[ -n "$OVERLAP_ANY" ]]; then
  check "native_overlap_risk" "FAIL (nativeVis>0 but native=0 + multi paint)"
  fail=1
elif [[ -n "$OVERLAP_HOSTILE" ]]; then
  check "native_overlap_risk" "FAIL (hostile native=0 multi-icon)"
  fail=1
elif rg -q 'PAINT ver=.*native=0.*miss=[2-9].*painted=[2-9]' "$SV_DATA" 2>/dev/null; then
  check "native_overlap_risk" "WARN (native=0 stacked gaps — check layout)"
  fail=1
elif rg -q 'PAINT ver=.*native=0.*painted=[2-9]' "$SV_DATA" 2>/dev/null; then
  check "native_overlap_risk" "FAIL (native=0 multi-paint)"
  fail=1
else
  check "native_overlap_risk" "WAIT (no multi-paint sample)"
fi

MULTI_SLOT="$(rg 'PAINT ver=' "$SV_DATA" 2>/dev/null | rg 'painted=[2-9]' | rg 'native=0' | tail -5 || true)"
NATIVEVIS_GAP="$(rg 'PAINT ver=' "$SV_DATA" 2>/dev/null | rg 'native=0' | rg 'nativeVis=[1-9]' | rg 'painted=[2-9]' | tail -5 || true)"
if [[ -n "$NATIVEVIS_GAP" ]]; then
  check "multi_icon_overlap" "FAIL (native=0 nativeVis≥1 multi-paint)"
  fail=1
elif [[ -n "$MULTI_SLOT" ]] && echo "$MULTI_SLOT" | rg -q 'nativeVis=0'; then
  check "multi_icon_overlap" "FAIL (painted≥2 nativeVis=0 — Tarantula-class stack)"
  fail=1
elif [[ -n "$MULTI_SLOT" ]]; then
  # nativeVis absent (pre-0.2.69) still means layout overlap risk — never OK
  check "multi_icon_overlap" "FAIL (painted≥2 native=0 — spacing telemetry pending)"
  fail=1
elif rg -q 'PAINT ver=.*painted=[2-9].*nativeVis=0.*miss=[2-9]' "$SV_DATA" 2>/dev/null; then
  check "multi_icon_overlap" "FAIL (painted≥2 no native spacing)"
  fail=1
else
  check "multi_icon_overlap" "WAIT (no multi-paint sample)"
fi

STALE_SRC="$PB_SV"
if rg -q 'paint_stale_cleared' "$STALE_SRC" 2>/dev/null; then
  check "prune_stale" "OK"
elif [[ -f "${PB_AGENT_LOG:-}" ]] && rg -q 'paint_stale_cleared' "$PB_AGENT_LOG" 2>/dev/null; then
  check "prune_stale" "OK"
else
  check "prune_stale" "WAIT (no expire repro)"
fi

echo "MATRIX context: live_ver=$PB_LIVE_VER flushed=$PB_FLUSHED_VER flush_lag=$PB_FLUSH_LAG"
[[ "$fail" -eq 0 ]] && echo "MATRIX pass (live $PB_LIVE_VER)" && exit 0
echo "MATRIX incomplete or fail — keep watching"
exit 1