#!/usr/bin/env bash
# FElog live feed gate — file age ≤MAX_AGE (default 5s), session ver vs Plateband TOC.
# Usage: ./scripts/felog-live-gate.sh [--max-age N]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/felog-sv-lib.sh
source "$ROOT/scripts/felog-sv-lib.sh"

MAX_AGE="${FELIVE_MAX_AGE:-5}"
if [[ "${1:-}" == "--max-age" && -n "${2:-}" ]]; then
  MAX_AGE="$2"
fi

felog_sync_repo_mirror 2>/dev/null || true

HEAD="$(felog_pick_live_head_file 2>/dev/null || true)"
[[ -n "$HEAD" ]] || HEAD="$(felog_live_head_path)"
EXPORT="$(felog_agent_export_path)"
STREAM="$(felog_live_stream_path)"
PB_IFACE="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
FE_IFACE="$(felog_interface_ver 2>/dev/null || echo "?")"

RES="$(felog_resolve_session_ver 2>/dev/null || true)"
SESSION_VER="$(echo "$RES" | sed -n 's/.*session_ver=\([^ ]*\).*/\1/p')"
SOURCE="$(echo "$RES" | sed -n 's/.*source=\([^ ]*\).*/\1/p')"
AGE="$(echo "$RES" | sed -n 's/.*age_sec=\([^ ]*\).*/\1/p')"

HEAD_LINE=""
if [[ -f "$HEAD" ]]; then
  HEAD_LINE="$(head -1 "$HEAD" 2>/dev/null || true)"
fi
HEAD_PB="$(sed -n 's/.*plateband_ver=\([0-9.]*\).*/\1/p' <<<"${HEAD_LINE}" | head -1)"
HEAD_FE="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"${HEAD_LINE}" | head -1)"
HEAD_LOAD="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"${HEAD_LINE}" | head -1)"

# Chat / TOC interface is ground truth. Stale SV or load=prove head = reader/publish lag, not "need reload".
CHAT_TRUTH_PB="$PB_IFACE"
CHAT_TRUTH_FE="$FE_IFACE"

if [[ ! -f "$HEAD" ]]; then
  echo "FELOG_GATE fail: missing live-head.log ($HEAD) — PublishChatTruthHead not on disk yet (chat truth pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE)"
  if [[ -f "$EXPORT" ]]; then
    echo "FELOG_GATE note: agent-live-export exists age=$(felog_file_age_sec "$EXPORT" 2>/dev/null || echo ?)s"
    tail -2 "$EXPORT" 2>/dev/null | sed 's/^/  /' || true
  elif [[ -f "$STREAM" ]]; then
    echo "FELOG_GATE note: live-stream.log exists (no head yet)"
    tail -2 "$STREAM" 2>/dev/null | sed 's/^/  /' || true
  fi
  echo "FELOG_GATE disk: chat_truth pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE session_ver=${SESSION_VER:-?} (ignore lagging SV)"
  exit 1
fi

if [[ "$HEAD_LOAD" == prove ]]; then
  echo "FELOG_GATE fail: reject load=prove stub (not chat truth) — expect PublishChatTruthHead pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE"
  head -1 "$HEAD"
  exit 1
fi

if [[ -n "$HEAD_PB" && -n "$CHAT_TRUTH_PB" && "$HEAD_PB" != "$CHAT_TRUTH_PB" ]]; then
  echo "FELOG_GATE fail: head_lag plateband_ver=$HEAD_PB != chat_truth=$CHAT_TRUTH_PB (SV/head lagging chat)"
  head -1 "$HEAD"
  exit 1
fi

if [[ -n "$HEAD_FE" && -n "$CHAT_TRUTH_FE" && "$HEAD_FE" != "$CHAT_TRUTH_FE" ]]; then
  echo "FELOG_GATE fail: head_lag felog_ver=$HEAD_FE != chat_truth=$CHAT_TRUTH_FE (SV/head lagging chat)"
  head -1 "$HEAD"
  exit 1
fi

if [[ ! "$AGE" =~ ^[0-9]+$ ]] || [[ "$AGE" -gt "$MAX_AGE" ]]; then
  echo "FELOG_GATE fail: live-head stale age=${AGE:-?}s max=${MAX_AGE}s — pulse/PublishChatTruthHead lag (chat truth pb=$CHAT_TRUTH_PB fe=$CHAT_TRUTH_FE)"
  head -1 "$HEAD"
  exit 1
fi

HEAD_LAG=no
if [[ -n "$CHAT_TRUTH_PB" && -n "$SESSION_VER" && "$CHAT_TRUTH_PB" != "$SESSION_VER" && "$SESSION_VER" != "?" ]]; then
  HEAD_LAG=yes
fi

if [[ "$HEAD_LAG" == yes ]]; then
  echo "FELOG_GATE fail: head_lag session_ver=$SESSION_VER != chat_truth=$CHAT_TRUTH_PB (reader must not invent reload_pending)"
  head -1 "$HEAD"
  exit 1
fi

echo "FELOG_GATE ok: pb=$HEAD_PB fe=$HEAD_FE chat_truth_pb=$CHAT_TRUTH_PB chat_truth_fe=$CHAT_TRUTH_FE source=$SOURCE age=${AGE}s max_age=${MAX_AGE}s load=${HEAD_LOAD:-?}"
head -1 "$HEAD"
exit 0