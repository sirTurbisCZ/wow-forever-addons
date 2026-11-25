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
  rg -q 'PLATES_LOAD ok=1' "$PB_SV" || { echo "MATRIX fail: PLATES_LOAD"; exit 1; }
fi

fail=0
check() { echo "  $1: $2"; [[ "$2" == "OK" ]] || fail=1; }

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
if echo "$HOSTILE" | rg -q 'painted=[1-9]'; then
  check "own_foreign_paint" "OK"
else
  check "own_foreign_paint" "WAIT (no hostile target=yes painted>0 in data)"
fi

if echo "$HOSTILE" | rg -q 'tgtSrc=1.*painted=[1-9]'; then
  check "tgt_bind" "OK"
else
  check "tgt_bind" "WAIT"
fi

FRIEND="$(rg 'PLATEBAND_CARD.*friend=1' "$SV_DATA" 2>/dev/null | tail -3 || true)"
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