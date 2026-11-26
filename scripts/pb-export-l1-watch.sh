#!/usr/bin/env bash
# Mac host: restamp Plateband agent-live-export.log L1 every ≤2s (no WoW /reload).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"

INTERVAL="${PB_EXPORT_L1_WATCH_SEC:-2}"
LOG="${PB_EXPORT_L1_WATCH_LOG:-$ROOT/addons/Plateband/Logs/export-l1-watch.log}"
MAX_AGE="${PB_EXPORT_PROMOTE_MAX_AGE:-120}"

mkdir -p "$(dirname "$LOG")"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") pb-export-l1-watch start interval=${INTERVAL}s max_age=${MAX_AGE}" | tee -a "$LOG"

while true; do
  TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if pb_sync_export_l1_active "$MAX_AGE" 2>/dev/null; then
  exp="$(felog_plateband_export_path)"
  age="$(felog_head_age_sec "$exp" 2>/dev/null || echo "?")"
    echo "[$TS] sync ok age=${age}s path=$exp" >>"$LOG"
  else
    echo "[$TS] sync fail" >>"$LOG"
  fi
  sleep "$INTERVAL"
done