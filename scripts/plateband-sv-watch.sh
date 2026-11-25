#!/usr/bin/env bash
# Background SV/FElog watch — run in tmux; agent polls without pinging player.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTERVAL="${PLATEBAND_SV_WATCH_SEC:-15}"
GATE="$ROOT/scripts/plateband-sv-gate.sh"
LOG="${PLATEBAND_SV_WATCH_LOG:-$ROOT/addons/Plateband/Logs/sv-watch.log}"

mkdir -p "$(dirname "$LOG")"

echo "plateband-sv-watch interval=${INTERVAL}s log=$LOG" | tee -a "$LOG"
while true; do
  TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if OUT="$("$GATE" 2>&1)"; then
    echo "[$TS] $OUT" >> "$LOG"
  else
    CODE=$?
    echo "[$TS] CODE=$CODE $OUT" >> "$LOG"
  fi
  "$ROOT/scripts/watch-plateband-sv.sh" 5 >> "$LOG" 2>&1 || true
  sleep "$INTERVAL"
done