#!/usr/bin/env bash
# Fast SESSION_START poll (~2s) — logs SESSION_REPORT immediately; full gate stays on 15s watch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTERVAL="${PLATEBAND_SESSION_POLL_SEC:-2}"
LOG="${PLATEBAND_SESSION_LOG:-$ROOT/addons/Plateband/Logs/session-watch.log}"
LATEST="${PLATEBAND_SESSION_LATEST:-$ROOT/addons/Plateband/Logs/session-report-latest.txt}"
REPORT="$ROOT/scripts/plateband-sv-session-report.sh"

mkdir -p "$(dirname "$LOG")"
echo "plateband-sv-session-watch interval=${INTERVAL}s log=$LOG" | tee -a "$LOG"

while true; do
  TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  set +e
  OUT="$("$REPORT" 2>&1)"
  RC=$?
  set -e
  if [[ "$RC" -eq 0 ]]; then
    echo "[$TS] $OUT" | tee -a "$LOG"
    printf '%s\n%s\n' "$TS" "$OUT" > "$LATEST"
  elif [[ "$RC" -ne 3 && -n "$OUT" ]]; then
    echo "[$TS] rc=$RC $OUT" >> "$LOG"
  fi
  sleep "$INTERVAL"
done