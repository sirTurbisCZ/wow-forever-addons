#!/usr/bin/env bash
# FElog live gate — SV chatTruthLine vs Interface TOC (disk optional; no host PASS).
# Usage: ./scripts/felog-live-gate.sh [--max-age N]
# Optional: FELIVE_HOST_PATCH=1 to allow pb_refresh (never counts as PASS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"

MAX_AGE="${FELIVE_MAX_AGE:-99999}"
if [[ "${1:-}" == "--max-age" && -n "${2:-}" ]]; then
  MAX_AGE="$2"
fi

felog_sync_repo_mirror 2>/dev/null || true
if [[ "${FELIVE_HOST_PATCH:-0}" == "1" ]]; then
  pb_refresh_export_line1_from_toc "${MAX_AGE}" 2>/dev/null || true
fi

PB_IFACE="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
FE_IFACE="$(felog_interface_ver 2>/dev/null || echo "?")"
CHAT_TRUTH_PB="$PB_IFACE"
CHAT_TRUTH_FE="$FE_IFACE"

SV_TRUTH="$(felog_read_chat_truth_sv 2>/dev/null || true)"
SV_LINE="$(echo "$SV_TRUTH" | sed -n 's/.*line=//p' | head -1)"
SV_PB="$(echo "$SV_TRUTH" | sed -n 's/.*plateband_ver=\([^ ]*\).*/\1/p')"
SV_FE="$(echo "$SV_TRUTH" | sed -n 's/.*felog_ver=\([^ ]*\).*/\1/p')"
SV_AGE="$(echo "$SV_TRUTH" | sed -n 's/.*age_sec=\([^ ]*\).*/\1/p')"
SV_SRC="$(echo "$SV_TRUTH" | sed -n 's/.*truth_src=\([^ ]*\).*/\1/p')"
SV_FEED="$(echo "$SV_TRUTH" | sed -n 's/.* feed=\([^ ]*\).*/\1/p')"
SV_LOAD="$(echo "$SV_TRUTH" | sed -n 's/.* load=\([^ ]*\).*/\1/p' | head -1)"
[[ -n "$SV_PB" ]] || SV_PB="$(echo "$SV_LINE" | sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p')"

DISK_EXP="$(felog_plateband_export_path)"
DISK_L1=""
DISK_FEED=""
DISK_AGE=9999
DISK_BONUS=no
if [[ -f "$DISK_EXP" ]]; then
  DISK_L1="$(head -1 "$DISK_EXP" 2>/dev/null || true)"
  DISK_FEED="$(sed -n 's/.* feed=\([^ ]*\).*/\1/p' <<<"$DISK_L1" | head -1)"
  DISK_AGE="$(felog_head_age_sec "$DISK_EXP" 2>/dev/null || echo 9999)"
fi

if [[ -z "$SV_LINE" ]]; then
  echo "FELOG_GATE fail: no PlatebandDB.chatTruthLine in SV — client login export not persisting (toc pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE)"
  [[ -f "$DISK_EXP" ]] && echo "FELOG_GATE note: disk L1=$(head -1 "$DISK_EXP" 2>/dev/null | cut -c1-80)"
  exit 1
fi

if [[ "$SV_FEED" == host_toc_pulse ]]; then
  echo "FELOG_GATE fail: SV chatTruthLine feed=host_toc_pulse — not client truth (pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE)"
  echo "  sv_line=$(echo "$SV_LINE" | cut -c1-100)"
  exit 1
fi
if [[ "$SV_LOAD" == "watch_sync" || "$SV_LOAD" == "host_toc_pulse" ]]; then
  echo "FELOG_GATE fail: SV load=$SV_LOAD — host restamp cannot PASS"
  echo "$SV_LINE"
  exit 1
fi
if [[ "$DISK_FEED" == host_toc_pulse ]]; then
  echo "FELOG_GATE note: disk L1 host_toc_pulse (ignored)"
fi

DISK_PB="$(echo "$DISK_L1" | sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' | head -1)"
DISK_FE="$(echo "$DISK_L1" | sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' | head -1)"
DISK_LOAD="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"$DISK_L1" | head -1)"
if [[ -f "$DISK_EXP" ]] && [[ "$DISK_L1" == live_ver=* ]] && [[ "$DISK_LOAD" != "watch_sync" ]]; then
  if felog_export_l1_is_client_pulse "$DISK_L1" \
    && [[ "$DISK_PB" == "$CHAT_TRUTH_PB" && "$DISK_FE" == "$CHAT_TRUTH_FE" ]] \
    && [[ "$DISK_AGE" =~ ^[0-9]+$ ]] && [[ "$DISK_AGE" -le 120 ]]; then
    DISK_BONUS=yes
  fi
fi

if [[ -n "$SV_PB" && "$SV_PB" != "$CHAT_TRUTH_PB" ]]; then
  echo "FELOG_GATE fail: sv_chat_truth plateband_ver=$SV_PB != toc=$CHAT_TRUTH_PB (disk_bonus=${DISK_BONUS} disk_pb=${DISK_PB:-?} disk_age=${DISK_AGE}s)"
  echo "$SV_LINE"
  exit 1
fi

if [[ -n "$SV_FE" && "$SV_FE" != "$CHAT_TRUTH_FE" ]]; then
  echo "FELOG_GATE fail: sv_chat_truth felog_ver=$SV_FE != toc=$CHAT_TRUTH_FE"
  echo "$SV_LINE"
  exit 1
fi

if [[ "$DISK_BONUS" == yes ]]; then
  echo "FELOG_GATE ok: pb=$SV_PB fe=$SV_FE chat_truth_pb=$CHAT_TRUTH_PB chat_truth_fe=$CHAT_TRUTH_FE source=sv_chat_truth+disk_bonus age=${SV_AGE:-?}s disk_age=${DISK_AGE}s truth_src=${SV_SRC:-?}"
else
  echo "FELOG_GATE ok: pb=$SV_PB fe=$SV_FE chat_truth_pb=$CHAT_TRUTH_PB chat_truth_fe=$CHAT_TRUTH_FE source=sv_chat_truth age=${SV_AGE:-?}s disk_age=${DISK_AGE}s io_note=optional_disk truth_src=${SV_SRC:-?}"
fi
echo "$SV_LINE"
exit 0