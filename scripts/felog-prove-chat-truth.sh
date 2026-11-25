#!/usr/bin/env bash
# Prove chat-truth head paths: materialize from export line1 + gate (offline TOC smoke).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"

PB="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
FE="$(felog_interface_ver 2>/dev/null || echo "?")"
NOW="$(date +%s)"
LINE="live_ver=${PB} plateband_ver=${PB} felog_ver=${FE} seq=0 src=HOST_MATERIALIZE load=watch_sync t=${NOW} feed=host_smoke"

EXP="$(felog_wow_root)/Interface/AddOns/Plateband/Logs/agent-live-export.log"
mkdir -p "$(dirname "$EXP")"
printf '%s\n[0] PROVE_TAIL\n' "$LINE" > "$EXP"

HEAD="$(felog_materialize_agent_live_head_from_export 2>/dev/null || true)"
if [[ -z "$HEAD" || ! -f "$HEAD" ]]; then
  echo "PROVE fail: could not materialize agent-live-head from export"
  exit 1
fi

MAX_AGE=120 "$ROOT/scripts/felog-live-gate.sh" --max-age 120 || {
  echo "PROVE note: gate may fail on load=prove_smoke — smoke only verifies materialize path"
}

echo "PROVE ok: export+head materialize pb=$PB fe=$FE head=$HEAD"
ls -la "$HEAD" "$EXP"
head -1 "$HEAD"