#!/usr/bin/env bash
# Refresh Plateband/Logs/interface-toc.ver from deployed Interface Config (gate truth).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"
PB="$(felog_plateband_interface_ver)"
FE="$(felog_interface_ver)"
STAMP="$(felog_wow_root)/Interface/AddOns/Plateband/Logs/interface-toc.ver"
mkdir -p "$(dirname "$STAMP")"
printf 'pb=%s fe=%s t=%s\n' "$PB" "$FE" "$(date +%s)" >"$STAMP"
echo "interface-toc.ver pb=$PB fe=$FE"