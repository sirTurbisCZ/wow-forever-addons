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

if [[ ! -f "$HEAD" ]]; then
  echo "FELOG_GATE fail: missing live-head.log ($HEAD) — need /reload on ForeverErrorLog 0.1.4+ (file feed, not WTF)"
  if [[ -f "$EXPORT" ]]; then
    echo "FELOG_GATE note: agent-live-export exists age=$(felog_file_age_sec "$EXPORT" 2>/dev/null || echo ?)s"
    tail -2 "$EXPORT" 2>/dev/null | sed 's/^/  /' || true
  elif [[ -f "$STREAM" ]]; then
    echo "FELOG_GATE note: live-stream.log exists (no head yet)"
    tail -2 "$STREAM" 2>/dev/null | sed 's/^/  /' || true
  fi
  echo "FELOG_GATE disk: pb_iface=$PB_IFACE fe_iface=$FE_IFACE session_ver=${SESSION_VER:-?} (SV may lag ~90s)"
  exit 1
fi

if [[ "$HEAD_LOAD" == prove ]]; then
  echo "FELOG_GATE fail: stale host prove stub — delete live-head and /reload (need chat-truth publish)"
  head -1 "$HEAD"
  exit 1
fi

if [[ -n "$HEAD_PB" && -n "$PB_IFACE" && "$HEAD_PB" != "$PB_IFACE" ]]; then
  echo "FELOG_GATE fail: head plateband_ver=$HEAD_PB != interface=$PB_IFACE (chat truth mismatch)"
  head -1 "$HEAD"
  exit 1
fi

if [[ -n "$HEAD_FE" && -n "$FE_IFACE" && "$HEAD_FE" != "$FE_IFACE" ]]; then
  echo "FELOG_GATE fail: head felog_ver=$HEAD_FE != interface=$FE_IFACE (chat truth mismatch)"
  head -1 "$HEAD"
  exit 1
fi

if [[ ! "$AGE" =~ ^[0-9]+$ ]] || [[ "$AGE" -gt "$MAX_AGE" ]]; then
  echo "FELOG_GATE fail: live-head stale age=${AGE:-?}s max=${MAX_AGE}s — pulse broken or client not running"
  head -1 "$HEAD"
  exit 1
fi

RELOAD=no
if [[ -n "$PB_IFACE" && -n "$SESSION_VER" && "$PB_IFACE" != "$SESSION_VER" && "$SESSION_VER" != "?" ]]; then
  RELOAD=yes
fi

if [[ "$RELOAD" == yes ]]; then
  echo "FELOG_GATE warn: reload_pending=yes session=$SESSION_VER pb_iface=$PB_IFACE fe_iface=$FE_IFACE source=$SOURCE age=${AGE}s"
else
  echo "FELOG_GATE ok: pb=$HEAD_PB fe=$HEAD_FE pb_iface=$PB_IFACE fe_iface=$FE_IFACE source=$SOURCE age=${AGE}s max_age=${MAX_AGE}s"
fi

head -1 "$HEAD"
exit 0