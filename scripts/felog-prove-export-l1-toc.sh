#!/usr/bin/env bash
# Prove client export L1 matches Interface Config/TOC (same as gate).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"

MAX_AGE="${1:-5}"
PB="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
FE="$(felog_interface_ver 2>/dev/null || echo "?")"
EXP="$(felog_plateband_export_path)"

if [[ ! -f "$EXP" ]]; then
  echo "PROVE_L1 fail: missing export $EXP"
  exit 1
fi

L1="$(head -1 "$EXP" 2>/dev/null || true)"
pb_sync_export_l1_active "$MAX_AGE" 2>/dev/null || true
L1="$(head -1 "$EXP" 2>/dev/null || true)"
AGE="$(felog_head_age_sec "$EXP" 2>/dev/null || echo 9999)"
MTIME="$(felog_file_age_sec "$EXP" 2>/dev/null || echo "?")"
T_AGE="$(felog_line_t_age_sec "$L1" 2>/dev/null || echo "?")"
LIVE="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$L1" | head -1)"
IPB="$(sed -n 's/.*interface_pb=\([0-9.]*\).*/\1/p' <<<"$L1" | head -1)"
IFE="$(sed -n 's/.*interface_fe=\([0-9.]*\).*/\1/p' <<<"$L1" | head -1)"
FE_L="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"$L1" | head -1)"
SRC="$(sed -n 's/.*src=\([^ ]*\).*/\1/p' <<<"$L1" | head -1)"

if [[ "$L1" != live_ver=* ]]; then
  echo "PROVE_L1 fail: L1 not live_ver= line"
  echo "$L1"
  exit 1
fi

if [[ ! "$AGE" =~ ^[0-9]+$ ]] || [[ "$AGE" -gt "$MAX_AGE" ]]; then
  echo "PROVE_L1 fail: export stale age=${AGE}s max=${MAX_AGE}s"
  echo "$L1"
  exit 1
fi

for label in LIVE IPB IFE FE_L; do
  val="${!label}"
  if [[ -z "$val" ]]; then
    echo "PROVE_L1 fail: missing $label in L1"
    exit 1
  fi
done

if [[ "$LIVE" != "$PB" || "$IPB" != "$PB" ]]; then
  echo "PROVE_L1 fail: plateband L1=$LIVE interface_pb=$IPB != toc=$PB"
  echo "$L1"
  exit 1
fi

if [[ "$FE_L" != "$FE" || "$IFE" != "$FE" ]]; then
  echo "PROVE_L1 fail: felog L1=$FE_L interface_fe=$IFE != toc=$FE"
  echo "$L1"
  exit 1
fi

echo "PROVE_L1 ok: pb=$PB fe=$FE src=$SRC age=${AGE}s mtime=${MTIME}s t_age=${T_AGE}s"
echo "$L1"
exit 0