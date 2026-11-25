#!/usr/bin/env bash
# Emit SESSION_REPORT when a new Plateband SESSION_START appears (live feed > flushed SV).
# Agent: on new report, message coordinator with live_ver (chat/runtime truth).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/plateband-sv-lib.sh
source "$ROOT/scripts/plateband-sv-lib.sh"

STATE="${PLATEBAND_SESSION_STATE:-$ROOT/addons/Plateband/Logs/last-session-start.key}"
mkdir -p "$(dirname "$STATE")"

pb_sv_context || {
  echo "SESSION_REPORT skip=no_sv live_ver=${PLATEBAND_LIVE_VER:-?}"
  exit 2
}

SESSION_LINE=""
SESSION_T=""
SESSION_FLUSHED=""

if [[ -f "${PB_AGENT_LOG:-}" ]]; then
  SESSION_LINE="$(grep 'SESSION_START ver=' "$PB_AGENT_LOG" 2>/dev/null | tail -1 || true)"
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
if [[ -f "${PB_AGENT_LOG:-}" ]]; then
  LOAD_LINE="$(grep 'PLATES_LOAD ok=1' "$PB_AGENT_LOG" 2>/dev/null | tail -1 || true)"
fi
[[ -z "$LOAD_LINE" ]] && LOAD_LINE="$(rg 'PLATES_LOAD ok=1' "$PB_SV" 2>/dev/null | tail -1 || true)"

# Key = session identity only (not live_ver env) so a new reload always fires within ~2s.
KEY="${SESSION_T:-0}|${SESSION_FLUSHED:-?}"
if [[ -f "$STATE" ]] && [[ "$(cat "$STATE")" == "$KEY" ]]; then
  exit 3
fi
printf '%s' "$KEY" > "$STATE"

# Prefer flushed SESSION ver when it matches runtime (post-reload); else runtime/env live.
REPORT_LIVE="$PB_LIVE_VER"
if [[ -n "$SESSION_FLUSHED" ]] && [[ "$SESSION_FLUSHED" == "$PB_RUNTIME_VER" ]]; then
  REPORT_LIVE="$SESSION_FLUSHED"
elif [[ -n "$SESSION_FLUSHED" ]] && pb_ver_sort_ge "$SESSION_FLUSHED" "${PB_MIN_LIVE_VER:-0.2.51}" && [[ "$PB_FLUSH_LAG" != "yes" ]]; then
  REPORT_LIVE="$SESSION_FLUSHED"
fi

CHAT_HINT="[Plateband] loaded v${REPORT_LIVE}"
echo "SESSION_REPORT new=1 live_ver=${REPORT_LIVE} flushed_session=${SESSION_FLUSHED:-?} runtime_ver=${PB_RUNTIME_VER} disk_ver=${PB_DISK_VER} flush_lag=${PB_FLUSH_LAG} t=${SESSION_T:-?} chat_hint=\"${CHAT_HINT}\" source=${PB_AGENT_LOG:-sv}"
[[ -n "$LOAD_LINE" ]] && echo "  PLATES_LOAD: $(echo "$LOAD_LINE" | tail -c 120)"
exit 0