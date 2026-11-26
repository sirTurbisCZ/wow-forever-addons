#!/usr/bin/env bash
# Version prove: SV chatTruthLine vs Interface Config/TOC (live-telemetry-options).
# Disk L1 is optional bonus only when client-authored CHAT_LOADED (not host restamp).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"

MAX_AGE="${1:-5}"
PB="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
FE="$(felog_interface_ver 2>/dev/null || echo "?")"
EXP="$(felog_plateband_export_path)"

SV_TRUTH="$(felog_read_chat_truth_sv 2>/dev/null || true)"
if [[ -z "$SV_TRUTH" ]]; then
  echo "PROVE_L1 fail: no PlatebandDB.chatTruthLine in SV — /reload after deploy (toc pb=$PB fe=$FE)"
  exit 1
fi

SV_LINE="$(echo "$SV_TRUTH" | sed -n 's/.*line=//p' | head -1)"
SV_PB="$(echo "$SV_TRUTH" | sed -n 's/.*plateband_ver=\([^ ]*\).*/\1/p')"
SV_FE="$(echo "$SV_TRUTH" | sed -n 's/.*felog_ver=\([^ ]*\).*/\1/p')"
SV_SRC="$(echo "$SV_TRUTH" | sed -n 's/.* src=\([^ ]*\).*/\1/p' | head -1)"
SV_LOAD="$(echo "$SV_TRUTH" | sed -n 's/.* load=\([^ ]*\).*/\1/p' | head -1)"
SV_FEED="$(echo "$SV_TRUTH" | sed -n 's/.* feed=\([^ ]*\).*/\1/p' | head -1)"
SV_AGE="$(echo "$SV_TRUTH" | sed -n 's/.*age_sec=\([^ ]*\).*/\1/p')"
[[ -n "$SV_PB" ]] || SV_PB="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$SV_LINE" | head -1)"
[[ -n "$SV_FE" ]] || SV_FE="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"$SV_LINE" | head -1)"

if [[ "$SV_FEED" == host_toc_pulse ]]; then
  echo "PROVE_L1 fail: SV feed=host_toc_pulse — not client truth"
  echo "$SV_LINE"
  exit 1
fi
if [[ "$SV_LOAD" == "watch_sync" || "$SV_LOAD" == "host_toc_pulse" ]]; then
  echo "PROVE_L1 fail: SV load=$SV_LOAD — host restamp"
  echo "$SV_LINE"
  exit 1
fi

if [[ "$SV_PB" != "$PB" ]]; then
  echo "PROVE_L1 fail: sv plateband_ver=$SV_PB != interface toc=$PB (age=${SV_AGE:-?}s — WTF flush lag OK after /reload)"
  echo "$SV_LINE"
  exit 1
fi
if [[ -n "$SV_FE" && "$SV_FE" != "$FE" ]]; then
  echo "PROVE_L1 fail: sv felog_ver=$SV_FE != interface toc=$FE"
  echo "$SV_LINE"
  exit 1
fi

DISK_BONUS=no
DISK_NOTE=""
if [[ -f "$EXP" ]]; then
  L1="$(head -1 "$EXP" 2>/dev/null | tr -d '\r' || true)"
  DISK_AGE="$(felog_head_age_sec "$EXP" 2>/dev/null || echo 9999)"
  DISK_LOAD="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"$L1" | head -1)"
  if [[ "$DISK_LOAD" == "watch_sync" || "$DISK_LOAD" == "host_toc_pulse" ]]; then
    DISK_NOTE="disk_ignored_host_restamp"
  elif felog_export_l1_is_client_pulse "$L1" 2>/dev/null; then
    DISK_PB="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$L1" | head -1)"
    DISK_FE="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"$L1" | head -1)"
    if [[ "$DISK_PB" == "$PB" && "$DISK_FE" == "$FE" ]] \
      && [[ "$DISK_AGE" =~ ^[0-9]+$ ]] && [[ "$DISK_AGE" -le "$MAX_AGE" ]]; then
      DISK_BONUS=yes
    else
      DISK_NOTE="disk_client_but_stale_or_ver_mismatch age=${DISK_AGE}s"
    fi
  else
    DISK_NOTE="disk_not_client_authored"
  fi
fi

echo "PROVE_L1 ok: pb=$PB fe=$FE truth=sv_chat_truth src=${SV_SRC:-?} load=${SV_LOAD:-?} sv_age=${SV_AGE:-?}s disk_bonus=$DISK_BONUS ${DISK_NOTE:+$DISK_NOTE}"
echo "$SV_LINE"
exit 0