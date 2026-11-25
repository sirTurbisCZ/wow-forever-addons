#!/usr/bin/env bash
# Shared Plateband SV readers — live runtime vs flushed disk (never conflate).
set -euo pipefail

pb_ver_sort_ge() {
  local a="$1" b="$2"
  [[ -n "$a" && -n "$b" ]] || return 1
  [[ "$(printf '%s\n' "$b" "$a" | sort -V | tail -1)" == "$a" ]]
}

pb_lib_root() {
  local d
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s' "$d"
}

pb_wow_root() {
  local r="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
  r="${r%/}"
  printf '%s' "$r"
}

pb_disk_ver() {
  local root cfg
  root="$(pb_lib_root)"
  cfg="$root/addons/Plateband/Config.lua"
  rg -o 'Config\.VERSION = "([^"]+)"' "$cfg" | sed 's/.*"\(.*\)".*/\1/'
}

pb_runtime_ver() {
  local wow cfg repo
  wow="$(pb_wow_root)"
  cfg="$wow/Interface/AddOns/Plateband/Config.lua"
  if [[ -f "$cfg" ]]; then
    rg -o 'Config\.VERSION = "([^"]+)"' "$cfg" | sed 's/.*"\(.*\)".*/\1/'
    return 0
  fi
  pb_disk_ver
}

pb_find_sv() {
  local wow f
  wow="$(pb_wow_root)"
  PB_SV=""
  while IFS= read -r f; do
    [[ -z "$PB_SV" || "$f" -nt "$PB_SV" ]] && PB_SV="$f"
  done < <(find "${wow}/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' 2>/dev/null)
  [[ -n "${PB_SV:-}" && -f "$PB_SV" ]]
}

pb_flushed_session_ver() {
  local sv="$1" v
  v="$(rg -o 'SESSION_START ver=[0-9.]+' "$sv" 2>/dev/null | tail -1 | sed 's/.*=//' || true)"
  if [[ -z "$v" ]]; then
    v="$(rg -o '\["export"\][^"]*SESSION_START ver=[0-9.]+' "$sv" 2>/dev/null | tail -1 | sed 's/.*ver=//' | sed 's/ .*//' || true)"
  fi
  printf '%s' "$v"
}

pb_flushed_plates_load() {
  local sv="$1"
  rg 'PLATES_LOAD ok=1' "$sv" 2>/dev/null | tail -1 || true
}

pb_last_diag_card() {
  local sv="$1"
  sed -n 's/.*\["card"\] = "\([^"]*\)".*/\1/p' "$sv" | tail -1
}

pb_ver_from_card() {
  local card="$1"
  echo "$card" | sed -n 's/.*ver=\([0-9.]*\).*/\1/p' | head -1
}

pb_find_agent_live_log() {
  local wow f pick
  wow="$(pb_wow_root)"
  pick=""
  while IFS= read -r f; do
    [[ -z "$pick" || "$f" -nt "$pick" ]] && pick="$f"
  done < <(find "${wow}" -name 'agent-live.log' -path '*/Plateband/Logs/*' 2>/dev/null)
  printf '%s' "$pick"
}

pb_agent_live_card() {
  local log="$1"
  [[ -f "$log" ]] || return 1
  tail -1 "$log" 2>/dev/null | sed -n 's/.*\(PLATEBAND_CARD .*\)/\1/p'
}

pb_agent_live_ver() {
  local log="$1" line v
  [[ -f "$log" ]] || return 1
  line="$(grep 'SESSION_START ver=' "$log" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*SESSION_START ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v" && return 0
  line="$(grep 'PLATES_LOAD ok=1' "$log" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*PLATES_LOAD ok=1 ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v" && return 0
  line="$(grep 'PLATEBAND_CARD' "$log" 2>/dev/null | tail -1 || true)"
  v="$(pb_ver_from_card "$line")"
  [[ -n "$v" ]] && printf '%s' "$v"
}

# What Lua actually runs (SESSION / PLATES_LOAD / CARD) — never Interface Config.lua alone.
pb_client_ver() {
  local sv="$1" agent_log="$2"
  local v line

  if [[ -f "${agent_log:-}" ]]; then
    v="$(pb_agent_live_ver "$agent_log" 2>/dev/null || true)"
    [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  fi

  line="$(rg -o '\[[0-9]+\] SESSION_START ver=[0-9.]+' "$sv" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*SESSION_START ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  line="$(rg 'PLATES_LOAD ok=1 ver=' "$sv" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*PLATES_LOAD ok=1 ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  v="$(pb_flushed_session_ver "$sv")"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  v="$(pb_ver_from_card "$(pb_last_diag_card "$sv")")"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_resolve_live_ver() {
  local client_ver="$1" flushed="$2" agent_ver="${3:-}" diag_ver="${4:-}"
  local live="${PLATEBAND_LIVE_VER:-}"

  if [[ -n "$live" ]]; then
    printf '%s' "$live"
    return
  fi
  if [[ -n "$client_ver" ]]; then
    live="$client_ver"
  elif [[ -n "$agent_ver" ]]; then
    live="$agent_ver"
  elif [[ -n "$diag_ver" ]] && pb_ver_sort_ge "$diag_ver" "${PB_MIN_LIVE_VER:-0.2.51}"; then
    live="$diag_ver"
  elif [[ -n "$flushed" ]]; then
    live="$flushed"
  fi
  printf '%s' "$live"
}

# Sets PB_* globals. Returns 0 when SV found.
pb_sv_context() {
  PB_MIN_LIVE_VER="${PB_MIN_LIVE_VER:-0.2.51}"
  PB_DISK_VER="$(pb_disk_ver)"
  PB_RUNTIME_VER="$(pb_runtime_ver)"
  PB_SV=""
  if ! pb_find_sv; then
  PB_FLUSHED_VER=""
  PB_LIVE_VER="${PLATEBAND_LIVE_VER:-$PB_RUNTIME_VER}"
  PB_FLUSH_LAG=unknown
  PB_AGENT_LOG=""
  PB_LAST_CARD=""
    return 1
  fi
  PB_FLUSHED_VER="$(pb_flushed_session_ver "$PB_SV")"
  PB_AGENT_LOG="$(pb_find_agent_live_log)"
  PB_AGENT_VER="$(pb_agent_live_ver "$PB_AGENT_LOG" 2>/dev/null || true)"
  PB_LAST_CARD="$(pb_last_diag_card "$PB_SV")"
  PB_DIAG_VER="$(pb_ver_from_card "$PB_LAST_CARD")"
  PB_CLIENT_VER="$(pb_client_ver "$PB_SV" "$PB_AGENT_LOG")"
  PB_LIVE_VER="$(pb_resolve_live_ver "$PB_CLIENT_VER" "$PB_FLUSHED_VER" "$PB_AGENT_VER" "$PB_DIAG_VER")"

  PB_RELOAD_PENDING=no
  if [[ -n "$PB_RUNTIME_VER" && -n "$PB_LIVE_VER" && "$PB_RUNTIME_VER" != "$PB_LIVE_VER" ]]; then
    if pb_ver_sort_ge "$PB_RUNTIME_VER" "$PB_LIVE_VER"; then
      PB_RELOAD_PENDING=yes
    else
      PB_RELOAD_PENDING=behind
    fi
  fi

  if [[ -n "$PB_FLUSHED_VER" && -n "$PB_LIVE_VER" && "$PB_FLUSHED_VER" != "$PB_LIVE_VER" ]]; then
    PB_FLUSH_LAG=yes
  else
    PB_FLUSH_LAG=no
  fi
  return 0
}

pb_live_ver_ok() {
  local live="$1" disk="$2" min="${3:-0.2.51}"
  pb_ver_sort_ge "$live" "$min"
}

pb_export_session_line() {
  printf 'live_ver=%s client_ver=%s flushed_session=%s deployed_ver=%s disk_ver=%s reload_pending=%s flush_lag=%s sv=%s' \
    "${PB_LIVE_VER:-?}" "${PB_CLIENT_VER:-?}" "${PB_FLUSHED_VER:-?}" "${PB_RUNTIME_VER:-?}" \
    "${PB_DISK_VER:-?}" "${PB_RELOAD_PENDING:-no}" "${PB_FLUSH_LAG:-?}" "${PB_SV:-none}"
}

pb_best_card_lines() {
  local sv="$1" agent_log="$2" n="${3:-12}"
  if [[ -f "${agent_log:-}" ]]; then
    tail -"$n" "$agent_log" 2>/dev/null | grep -E 'PLATEBAND_CARD|PAINT ' || true
  fi
  rg 'PLATEBAND_CARD' "$sv" 2>/dev/null | tail -"$n" || true
}