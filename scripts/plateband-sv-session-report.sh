#!/usr/bin/env bash
# Emit SESSION_REPORT on new session, agentLive seq, or reload_pending transition.
# live_ver = client/session truth only (never TOC).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/plateband-sv-lib.sh
source "$ROOT/scripts/plateband-sv-lib.sh"

STATE="${PLATEBAND_SESSION_STATE:-$ROOT/addons/Plateband/Logs/last-session-start.key}"
MIRROR="${PLATEBAND_SV_MIRROR:-$ROOT/addons/Plateband/Logs/agent-live-export.log}"
mkdir -p "$(dirname "$STATE")"

pb_sv_context || {
  echo "SESSION_REPORT skip=no_sv deployed_ver=${PB_RUNTIME_VER:-?} disk_ver=${PB_DISK_VER:-?}"
  exit 2
}

pb_sync_live_feed "$PB_SV" 2>/dev/null || true
MIRROR="${PLATEBAND_SV_MIRROR:-$ROOT/addons/Plateband/Logs/agent-live-export.log}"

SESSION_LINE=""
SESSION_T=""
SESSION_FLUSHED=""

if [[ -n "${PB_AGENT_LOG:-}" ]] && pb_agent_log_fresh "$PB_AGENT_LOG" "$PB_SV"; then
  SESSION_LINE="$(grep 'SESSION_START ver=' "$PB_AGENT_LOG" 2>/dev/null | tail -1 || true)"
fi
if [[ -z "$SESSION_LINE" ]]; then
  SESSION_LINE="$(pb_sv_export_grep_last "$PB_SV" "SESSION_START" 2>/dev/null || true)"
fi
if [[ -z "$SESSION_LINE" ]]; then
  SESSION_LINE="$(rg 'SESSION_START ver=' "$PB_SV" 2>/dev/null | tail -1 || true)"
fi
if [[ -z "$SESSION_LINE" && -f "$PB_SV" ]]; then
  SESSION_LINE="$(sed -n 's/.*"\(\[[0-9]*\] SESSION_START[^"]*\)".*/\1/p' "$PB_SV" | tail -1)"
fi

SESSION_FLUSHED="$(echo "$SESSION_LINE" | sed -n 's/.*SESSION_START ver=\([0-9.]*\).*/\1/p')"
SESSION_T="$(echo "$SESSION_LINE" | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')"

LOAD_LINE=""
if [[ -n "${PB_AGENT_LOG:-}" ]] && pb_agent_log_fresh "$PB_AGENT_LOG" "$PB_SV"; then
  LOAD_LINE="$(grep 'PLATES_LOAD ok=1' "$PB_AGENT_LOG" 2>/dev/null | tail -1 || true)"
fi
if [[ -z "$LOAD_LINE" ]]; then
  LOAD_LINE="$(pb_sv_export_grep_last "$PB_SV" "PLATES_LOAD ok=1" 2>/dev/null || true)"
fi
[[ -z "$LOAD_LINE" ]] && LOAD_LINE="$(rg 'PLATES_LOAD ok=1' "$PB_SV" 2>/dev/null | tail -1 || true)"

AGENT_LINE="$(pb_sv_export_grep_last "$PB_SV" "AGENT_LIVE" 2>/dev/null || true)"
AGENT_SEQ="${PB_AGENT_SEQ:-0}"
RELOAD="${PB_RELOAD_PENDING:-no}"
KEY="${SESSION_T:-0}|${SESSION_FLUSHED:-?}|${AGENT_SEQ:-0}|${RELOAD}"

PREV_KEY="" PREV_RELOAD=""
if [[ -f "$STATE" ]]; then
  read -r PREV_KEY PREV_RELOAD < "$STATE" || true
fi
if [[ -n "$PREV_KEY" && "$KEY" == "$PREV_KEY" && "${RELOAD:-}" == "${PREV_RELOAD:-}" ]]; then
  exit 3
fi
printf '%s %s\n' "$KEY" "${RELOAD:-no}" > "$STATE"

REPORT_LIVE="${PB_LIVE_VER:-$PB_CLIENT_VER}"

CHAT_HINT="[Plateband] client v${REPORT_LIVE:-?}"
if [[ "${PB_RELOAD_PENDING:-no}" == "yes" ]]; then
  CHAT_HINT="[Plateband] client v${REPORT_LIVE:-?} (TOC/deployed ${PB_RUNTIME_VER:-?} — need /reload)"
elif [[ "${PB_RELOAD_PENDING:-no}" == "behind" ]]; then
  CHAT_HINT="[Plateband] client v${REPORT_LIVE:-?} (TOC ${PB_RUNTIME_VER:-?} older than client)"
fi

echo "SESSION_REPORT new=1 live_ver=${REPORT_LIVE:-?} client_ver=${PB_CLIENT_VER:-?} deployed_ver=${PB_RUNTIME_VER:-?} disk_ver=${PB_DISK_VER:-?} reload_pending=${RELOAD} flushed_session=${SESSION_FLUSHED:-?} flush_lag=${PB_FLUSH_LAG:-?} agent_seq=${AGENT_SEQ} feed=${PB_FEED_SOURCE:-?} t=${SESSION_T:-?} chat_hint=\"${CHAT_HINT}\" source=${PB_FEED_SOURCE:-sv} mirror=${MIRROR}"
[[ -n "$LOAD_LINE" ]] && echo "  PLATES_LOAD: $(echo "$LOAD_LINE" | rg -o '\[[0-9]+\] PLATES_LOAD[^\n]*' 2>/dev/null | tail -1 || echo "$LOAD_LINE" | tail -c 120)"
[[ -n "$AGENT_LINE" ]] && echo "  AGENT_LIVE: $(echo "$AGENT_LINE" | rg -o '\[[0-9]+\] AGENT_LIVE[^\n]*' 2>/dev/null | tail -1 || echo "$AGENT_LINE" | tail -c 120)"
exit 0