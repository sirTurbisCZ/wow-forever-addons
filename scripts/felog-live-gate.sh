#!/usr/bin/env bash
# FElog live feed gate — SV chatTruthLine (client pulse) is truth; disk is secondary.
# Usage: ./scripts/felog-live-gate.sh [--max-age N]
# Optional: FELIVE_HOST_PATCH=1 to allow pb_refresh (never counts as PASS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"

MAX_AGE="${FELIVE_MAX_AGE:-5}"
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
SV_SRC="$(echo "$SV_TRUTH" | sed -n 's/.* truth_src=\([^ ]*\).*/\1/p')"
SV_FEED="$(echo "$SV_TRUTH" | sed -n 's/.* feed=\([^ ]*\).*/\1/p')"
[[ -n "$SV_PB" ]] || SV_PB="$(echo "$SV_LINE" | sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p')"

DISK_EXP="$(felog_plateband_export_path)"
DISK_L1=""
DISK_FEED=""
DISK_AGE=9999
if [[ -f "$DISK_EXP" ]]; then
  DISK_L1="$(head -1 "$DISK_EXP" 2>/dev/null || true)"
  DISK_FEED="$(sed -n 's/.* feed=\([^ ]*\).*/\1/p' <<<"$DISK_L1" | head -1)"
  DISK_AGE="$(felog_head_age_sec "$DISK_EXP" 2>/dev/null || echo 9999)"
fi

if [[ -z "$SV_LINE" ]]; then
  echo "FELOG_GATE fail: no PlatebandDB.chatTruthLine in SV — client ExportTruthTicker not persisting (pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE)"
  [[ -f "$DISK_EXP" ]] && echo "FELOG_GATE note: disk L1=$(head -1 "$DISK_EXP" 2>/dev/null | cut -c1-80)"
  exit 1
fi

# Host-patched disk must never count as truth. SV chatTruthLine is the only PASS source.
if [[ "$SV_FEED" == host_toc_pulse ]]; then
  echo "FELOG_GATE fail: SV chatTruthLine feed=host_toc_pulse — not client truth (pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE)"
  echo "  sv_line=$(echo "$SV_LINE" | cut -c1-100)"
  exit 1
fi
if [[ "$DISK_FEED" == host_toc_pulse ]]; then
  echo "FELOG_GATE note: disk L1 still host_toc_pulse (ignored; gate uses SV chatTruthLine only)"
fi

DISK_PB="$(echo "$DISK_L1" | sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' | head -1)"
DISK_FE="$(echo "$DISK_L1" | sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' | head -1)"
DISK_TRUTH=no
if [[ -f "$DISK_EXP" ]] && [[ "$DISK_L1" == live_ver=* ]] && [[ "$DISK_FEED" == pb_bridge ]]; then
  if felog_export_l1_is_client_pulse "$DISK_L1" \
     && [[ "$DISK_PB" == "$CHAT_TRUTH_PB" && "$DISK_FE" == "$CHAT_TRUTH_FE" ]] \
     && [[ "$DISK_AGE" =~ ^[0-9]+$ ]] && [[ "$DISK_AGE" -le "$MAX_AGE" ]]; then
    DISK_TRUTH=yes
  fi
fi

SV_VER_OK=yes
if [[ -n "$SV_PB" && "$SV_PB" != "$CHAT_TRUTH_PB" ]]; then
  SV_VER_OK=no
fi
if [[ -n "$SV_FE" && "$SV_FE" != "$CHAT_TRUTH_FE" ]]; then
  SV_VER_OK=no
fi

if [[ "$SV_VER_OK" == no ]]; then
  if [[ "$DISK_TRUTH" == yes ]]; then
    echo "FELOG_GATE note: SV still $SV_PB/$SV_FE (wtf flush); disk export fresh $DISK_PB/$DISK_FE age=${DISK_AGE}s"
    SV_LINE="$DISK_L1"
    SV_PB="$DISK_PB"
    SV_FE="$DISK_FE"
    SV_AGE="$DISK_AGE"
    SV_SRC="disk_export"
  else
    echo "FELOG_GATE fail: sv_chat_truth plateband_ver=$SV_PB != toc=$CHAT_TRUTH_PB (disk_age=${DISK_AGE}s disk_pb=${DISK_PB:-?})"
    echo "$SV_LINE"
    exit 1
  fi
fi

if [[ -n "$SV_FE" && "$SV_FE" != "$CHAT_TRUTH_FE" ]] && [[ "$DISK_TRUTH" != yes ]]; then
  echo "FELOG_GATE fail: sv_chat_truth felog_ver=$SV_FE != toc=$CHAT_TRUTH_FE"
  echo "$SV_LINE"
  exit 1
fi

if [[ ! "$SV_AGE" =~ ^[0-9]+$ ]] || [[ "$SV_AGE" -gt "$MAX_AGE" ]]; then
  if [[ "$DISK_TRUTH" == yes ]]; then
    SV_LINE="$DISK_L1"
    SV_AGE="$DISK_AGE"
    SV_SRC="disk_export"
  else
    echo "FELOG_GATE fail: sv_chat_truth stale age=${SV_AGE:-?}s max=${MAX_AGE}s (client pulse lag; disk_age=${DISK_AGE}s disk_pb=${DISK_PB:-?})"
    echo "$SV_LINE"
    exit 1
  fi
fi

if [[ -f "$DISK_EXP" ]] && [[ "$DISK_L1" == live_ver=* ]] && [[ "$DISK_FEED" == pb_bridge ]]; then
  if [[ ! "$DISK_AGE" =~ ^[0-9]+$ ]] || [[ "$DISK_AGE" -gt "$MAX_AGE" ]]; then
    echo "FELOG_GATE fail: export disk stale age=${DISK_AGE}s max=${MAX_AGE}s — PulseExportDisk not writing (need /reload 0.2.85+)"
    [[ -n "$DISK_L1" ]] && echo "$DISK_L1"
    exit 1
  fi
  if [[ "$DISK_PB" != "$CHAT_TRUTH_PB" || "$DISK_FE" != "$CHAT_TRUTH_FE" ]]; then
    echo "FELOG_GATE fail: disk export ver ${DISK_PB:-?}/${DISK_FE:-?} != toc $CHAT_TRUTH_PB/$CHAT_TRUTH_FE"
    [[ -n "$DISK_L1" ]] && echo "$DISK_L1"
    exit 1
  fi
fi

DISK_OK=no
if [[ "$DISK_L1" == "$SV_LINE" ]] && [[ "$DISK_AGE" -le "$MAX_AGE" ]]; then
  DISK_OK=yes
fi

if [[ "$DISK_OK" == yes ]]; then
  echo "FELOG_GATE ok: pb=$SV_PB fe=$SV_FE chat_truth_pb=$CHAT_TRUTH_PB chat_truth_fe=$CHAT_TRUTH_FE source=sv_chat_truth+disk_sync age=${SV_AGE}s disk_age=${DISK_AGE}s truth_src=${SV_SRC:-?}"
else
  echo "FELOG_GATE ok: pb=$SV_PB fe=$SV_FE chat_truth_pb=$CHAT_TRUTH_PB chat_truth_fe=$CHAT_TRUTH_FE source=sv_chat_truth age=${SV_AGE}s disk_age=${DISK_AGE}s io_note=disk_lag truth_src=${SV_SRC:-?}"
  if [[ -n "$DISK_L1" && "$DISK_L1" != live_ver=* ]]; then
    echo "FELOG_GATE note: disk export L1 not live_ver= (watch reads SV truth; client io may be sv_only)"
  fi
fi
echo "$SV_LINE"
exit 0