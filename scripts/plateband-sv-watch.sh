#!/usr/bin/env bash
# Background SV/FElog watch — run in tmux; agent polls without pinging player.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTERVAL="${PLATEBAND_SV_WATCH_SEC:-15}"
GATE="$ROOT/scripts/plateband-sv-gate.sh"
ANOM="$ROOT/scripts/plateband-sv-anomaly.sh"
MATRIX="$ROOT/scripts/plateband-sv-matrix.sh"
LOG="${PLATEBAND_SV_WATCH_LOG:-$ROOT/addons/Plateband/Logs/sv-watch.log}"

mkdir -p "$(dirname "$LOG")"

SESSION_WATCH="$ROOT/scripts/plateband-sv-session-watch.sh"
if [[ -x "$SESSION_WATCH" ]] && [[ -z "${PLATEBAND_SESSION_WATCH_CHILD:-}" ]]; then
  export PLATEBAND_SESSION_WATCH_CHILD=1
  nohup env PLATEBAND_LIVE_VER="${PLATEBAND_LIVE_VER:-}" bash "$SESSION_WATCH" >> "$ROOT/addons/Plateband/Logs/session-watch.log" 2>&1 &
  echo "plateband-sv-watch session-poll child pid=$! interval=${PLATEBAND_SESSION_POLL_SEC:-2}s" | tee -a "$LOG"
fi

echo "plateband-sv-watch interval=${INTERVAL}s log=$LOG" | tee -a "$LOG"
echo "WATCH debuffs=HARMFUL+HELPFUL via CARD.tf PAINT.harv,miss,painted,friend,party sticky,foreign,WS,bleed" | tee -a "$LOG"
while true; do
  TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if OUT="$("$GATE" 2>&1)"; then
    echo "[$TS] $OUT" >> "$LOG"
  else
    CODE=$?
    echo "[$TS] CODE=$CODE $OUT" >> "$LOG"
  fi
  "$ROOT/scripts/watch-plateband-sv.sh" 5 >> "$LOG" 2>&1 || true
  if bash "$ANOM" >> "$LOG" 2>&1; then
    :
  else
    echo "[$TS] ANOMALY scan failed (see above)" >> "$LOG"
  fi
  bash "$MATRIX" >> "$LOG" 2>&1 || true
  set +e
  REP="$("$ROOT/scripts/plateband-sv-session-report.sh" 2>&1)"
  REP_RC=$?
  set -e
  if [[ "$REP_RC" -eq 0 ]]; then
    echo "[$TS] $REP" >> "$LOG"
  elif [[ "$REP_RC" -ne 3 && -n "$REP" ]]; then
    echo "[$TS] session-report rc=$REP_RC $REP" >> "$LOG"
  fi
  sleep "$INTERVAL"
done