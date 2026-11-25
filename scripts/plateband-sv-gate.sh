#!/usr/bin/env bash
# Validate Plateband paint signals — live_ver is runtime/chat, not stale flush alone.
set -euo pipefail

OFFLINE=0
[[ "${1:-}" == "--offline" ]] && { OFFLINE=1; shift; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/plateband-sv-lib.sh
source "$ROOT/scripts/plateband-sv-lib.sh"

if [[ "$OFFLINE" -eq 1 ]]; then
  exit 0
fi

if ! pb_sv_context; then
  echo "SV_GATE skip: no Plateband.lua (live_ver=${PLATEBAND_LIVE_VER:-${PB_RUNTIME_VER:-?}})"
  exit 2
fi

if ! pb_live_ver_ok "$PB_LIVE_VER" "$PB_DISK_VER"; then
  echo "SV_GATE fail: live_ver=$PB_LIVE_VER need>=${PB_MIN_LIVE_VER:-0.2.51} (deployed_toc=$PB_RUNTIME_VER flushed=$PB_FLUSHED_VER)"
  exit 1
fi

LOAD="$(pb_flushed_plates_load "$PB_SV")"
if [[ -z "$LOAD" ]]; then
  LOAD="$(rg 'PLATES_LOAD ok=1' "$PB_SV" 2>/dev/null | tail -1 || true)"
fi
EXPORT_LOAD="$(rg -o 'PLATES_LOAD ok=1[^\\n]*' "$PB_SV" 2>/dev/null | tail -1 || true)"
if [[ -z "$LOAD" && "$PB_FLUSH_LAG" != "yes" ]]; then
  echo "SV_GATE fail: no PLATES_LOAD ok=1 in SV/export (paint path may not have started)"
  exit 1
fi
if echo "$LOAD" | rg -q 'paint=false'; then
  echo "SV_GATE fail: PLATES_LOAD paint=false — PaintMergeMissing not loaded"
  echo "  $LOAD"
  exit 1
fi

if [[ "$PB_FLUSH_LAG" == "yes" ]]; then
  echo "SV_GATE note: flush_lag=yes — export may trail; feed=${PB_FEED_SOURCE:-?} agent_seq=${PB_AGENT_SEQ:-?}"
fi

if [[ "${PB_RELOAD_PENDING:-no}" == "yes" ]]; then
  if [[ "${PB_CHAT_OVERRIDE:-}" == yes && "${PB_LIVE_VER:-}" == "${PB_RUNTIME_VER:-}" ]]; then
    echo "SV_GATE note: reload_pending=no — chat/liveHead runtime matches deployed ${PB_RUNTIME_VER}"
  else
    echo "SV_GATE note: reload_pending=yes — client ${PB_LIVE_VER} < deployed ${PB_RUNTIME_VER} (TOC); paint rules apply to client ver until /reload"
  fi
fi

FELOG=""
while IFS= read -r f; do
  [[ -z "$FELOG" || "$f" -nt "$FELOG" ]] && FELOG="$f"
done < <(find "$(pb_wow_root)/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null)
if [[ -f "${FELOG:-}" ]] && rg -q "200 local variables" "$FELOG" 2>/dev/null; then
  if pb_ver_sort_ge "$PB_LIVE_VER" "0.2.47"; then
    echo "SV_GATE warn: FElog has historical 200-local errors (ignoring for live $PB_LIVE_VER)"
  fi
fi
if [[ -f "${FELOG:-}" ]] && rg -q 'more than 60 upvalues' "$FELOG" 2>/dev/null; then
  if rg 'more than 60 upvalues' "$FELOG" 2>/dev/null | tail -1 | rg -q "Plates"; then
    if ! echo "$LOAD" | rg -q 'PLATES_LOAD ok=1.*paint=true'; then
      echo "SV_GATE fail: PaintMergeMissing over 60 upvalues (Plates.lua) — split PlatesPaint required"
      exit 1
    fi
  fi
fi
if [[ -f "${FELOG:-}" ]] && rg -q 'Plateband:paint.*nil value' "$FELOG" 2>/dev/null; then
  if echo "$LOAD" | rg -q 'PLATES_LOAD ok=1.*paint=true'; then
    echo "SV_GATE note: FElog paint-nil entries are historical when PLATES_LOAD paint=true (live $PB_LIVE_VER)"
  else
    echo "SV_GATE fail: FElog paint nil and no PLATES_LOAD paint=true"
    exit 1
  fi
fi

# Prefer live log card for hostile tf>0 painted=0
CARD=""
if [[ -f "${PB_AGENT_LOG:-}" ]]; then
  CARD="$(grep 'PLATEBAND_CARD.*target=yes' "$PB_AGENT_LOG" 2>/dev/null | tail -1 || true)"
fi
if [[ -z "$CARD" ]]; then
  CARD="$(rg 'PLATEBAND_CARD.*target=yes' "$PB_SV" 2>/dev/null | tail -1 || true)"
fi
if [[ -z "$CARD" && -n "${PB_LAST_CARD:-}" ]]; then
  echo "$PB_LAST_CARD" | rg -q 'target=yes' && CARD="$PB_LAST_CARD"
fi

if [[ -n "$CARD" ]]; then
  if echo "$CARD" | rg -q 'tf=[1-9]' && echo "$CARD" | rg -q 'painted=0'; then
    if ! echo "$CARD" | rg -q 'friend=1'; then
      echo "SV_GATE fail: hostile target tf>0 but painted=0 (live_ver=$PB_LIVE_VER)"
      echo "  $CARD"
      exit 1
    fi
  fi
fi

echo "SV_GATE ok: $(pb_export_session_line)"
exit 0