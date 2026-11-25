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

# Runtime truth from PlatebandDB.agentLive (2s pulse, works when io=sv_only).
pb_runtime_ver_log() {
  local wow
  wow="$(pb_wow_root)"
  printf '%s' "$wow/Interface/AddOns/Plateband/Logs/runtime-ver.log"
}

pb_runtime_file_ver() {
  local f="$1" v
  [[ -f "$f" ]] || return 1
  v="$(grep 'RUNTIME_VER ver=' "$f" 2>/dev/null | tail -1 | sed -n 's/.*RUNTIME_VER ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_runtime_file_fresh() {
  local f="$1" sv="$2"
  [[ -f "$f" && -f "$sv" ]] || return 1
  local lm sm
  lm="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
  sm="$(stat -f %m "$sv" 2>/dev/null || stat -c %Y "$sv" 2>/dev/null || echo 0)"
  [[ "$lm" -ge "$((sm - 8))" ]]
}

pb_sv_runtime_table_ver() {
  local sv="$1" v
  [[ -f "$sv" ]] || return 1
  v="$(python3 - "$sv" <<'PY' 2>/dev/null || true
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
m = re.search(r'\["runtimeVer"\]\s*=\s*\{', t)
if not m:
    sys.exit(0)
chunk = t[m.start() : m.start() + 400]
vm = re.search(r'\["ver"\]\s*=\s*"([0-9.]+)"', chunk)
if vm:
    print(vm.group(1))
PY
)"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_sv_chat_loaded_ver() {
  local sv="$1" line v
  line="$(pb_sv_export_grep_last "$sv" "CHAT_LOADED" 2>/dev/null || true)"
  v="$(echo "$line" | sed -n 's/.*CHAT_LOADED ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_sv_agent_live_ver() {
  local sv="$1" v
  [[ -f "$sv" ]] || return 1
  v="$(python3 - "$sv" <<'PY' 2>/dev/null || true
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
m = re.search(r'\["agentLive"\]\s*=\s*\{', t)
if not m:
    sys.exit(0)
chunk = t[m.start() : m.start() + 800]
vm = re.search(r'\["ver"\]\s*=\s*"([0-9.]+)"', chunk)
if vm:
    print(vm.group(1))
PY
)"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_sv_agent_seq() {
  local sv="$1" s
  [[ -f "$sv" ]] || return 1
  s="$(python3 - "$sv" <<'PY' 2>/dev/null || true
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
m = re.search(r'\["agentLive"\]\s*=\s*\{', t)
if not m:
    sys.exit(0)
chunk = t[m.start() : m.start() + 800]
sm = re.search(r'\["seq"\]\s*=\s*(\d+)', chunk)
if sm:
    print(sm.group(1))
PY
)"
  [[ -n "$s" ]] && printf '%s' "$s"
}

pb_sv_export_grep_last() {
  local sv="$1" pattern="$2"
  [[ -f "$sv" ]] || return 1
  python3 - "$sv" "$pattern" <<'PY' 2>/dev/null || true
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
pat = sys.argv[2]
em = re.search(r'\["export"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if not em:
    sys.exit(0)
body = em.group(1).encode("utf-8").decode("unicode_escape")
hits = [ln for ln in body.split("\n") if pat in ln]
if hits:
    print(hits[-1])
PY
}

pb_agent_log_fresh() {
  local log="$1" sv="$2"
  [[ -f "$log" && -f "$sv" ]] || return 1
  local lm sm
  lm="$(stat -f %m "$log" 2>/dev/null || stat -c %Y "$log" 2>/dev/null || echo 0)"
  sm="$(stat -f %m "$sv" 2>/dev/null || stat -c %Y "$sv" 2>/dev/null || echo 0)"
  # File log only trusted when touched at or after last SV flush (Forever often blocks io).
  [[ "$lm" -ge "$((sm - 3))" ]] && rg -q 'SESSION_START|AGENT_LIVE|PLATEBAND_CARD' "$log" 2>/dev/null
}

pb_mirror_sv_export() {
  local sv="$1" out="$2"
  [[ -f "$sv" ]] || return 1
  mkdir -p "$(dirname "$out")"
  python3 - "$sv" "$out" <<'PY' || return 1
import pathlib, re, sys
src, dst = sys.argv[1], sys.argv[2]
t = pathlib.Path(src).read_text(errors="replace")
em = re.search(r'\["export"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
body = ""
if em:
    body = em.group(1).encode("utf-8").decode("unicode_escape")
if not body:
    al = re.search(r'\["agentLive"\]', t)
    if al:
        body = "# sv_only mirror — no export blob yet\n"
pathlib.Path(dst).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(dst).write_text(body[-48000:], encoding="utf-8")
PY
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
  local wow f pick name
  wow="$(pb_wow_root)"
  pick=""
  for name in runtime-ver.log agent-live.log agent-live-export.log session.log; do
    while IFS= read -r f; do
      [[ -z "$pick" || "$f" -nt "$pick" ]] && pick="$f"
    done < <(find "${wow}" -name "$name" -path '*/Plateband/Logs/*' 2>/dev/null)
  done
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
  if [[ -z "$line" ]]; then
    line="$(grep 'PLATEBAND_CARD ver=' "$log" 2>/dev/null | tail -1 || true)"
  fi
  v="$(echo "$line" | sed -n 's/.*SESSION_START ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v" && return 0
  line="$(grep 'PLATES_LOAD ok=1' "$log" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*PLATES_LOAD ok=1 ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v" && return 0
  line="$(grep 'PLATEBAND_CARD' "$log" 2>/dev/null | tail -1 || true)"
  v="$(pb_ver_from_card "$line")"
  [[ -n "$v" ]] && printf '%s' "$v"
}

# What Lua actually runs — SESSION / PLATES_LOAD / agentLive / export; never TOC alone.
pb_client_ver() {
  local sv="$1" agent_log="$2"
  local v line rvf

  rvf="$(pb_runtime_ver_log)"
  if [[ -f "$rvf" ]] && pb_runtime_file_fresh "$rvf" "$sv"; then
    v="$(pb_runtime_file_ver "$rvf" 2>/dev/null || true)"
    [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  fi

  v="$(pb_sv_runtime_table_ver "$sv" 2>/dev/null || true)"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  v="$(pb_sv_chat_loaded_ver "$sv" 2>/dev/null || true)"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  line="$(pb_sv_export_grep_last "$sv" "RUNTIME_VER" 2>/dev/null || true)"
  v="$(echo "$line" | sed -n 's/.*RUNTIME_VER ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  v="$(pb_sv_agent_live_ver "$sv" 2>/dev/null || true)"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  line="$(pb_sv_export_grep_last "$sv" "AGENT_LIVE" 2>/dev/null || true)"
  v="$(echo "$line" | sed -n 's/.*AGENT_LIVE ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  if [[ -n "${agent_log:-}" ]] && pb_agent_log_fresh "$agent_log" "$sv"; then
    v="$(pb_agent_live_ver "$agent_log" 2>/dev/null || true)"
    [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  fi

  line="$(pb_sv_export_grep_last "$sv" "SESSION_START" 2>/dev/null || true)"
  [[ -z "$line" ]] && line="$(rg -o '\[[0-9]+\] SESSION_START ver=[0-9.]+' "$sv" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*SESSION_START ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  line="$(pb_sv_export_grep_last "$sv" "PLATES_LOAD ok=1" 2>/dev/null || true)"
  [[ -z "$line" ]] && line="$(rg 'PLATES_LOAD ok=1 ver=' "$sv" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*PLATES_LOAD ok=1 ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  v="$(pb_flushed_session_ver "$sv")"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }

  line="$(pb_sv_export_grep_last "$sv" "PLATEBAND_CARD" 2>/dev/null || true)"
  v="$(pb_ver_from_card "$line")"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_resolve_live_ver() {
  local client_ver="$1" flushed="$2" agent_ver="${3:-}" diag_ver="${4:-}"
  local live=""
  if [[ -n "$client_ver" ]]; then
    live="$client_ver"
  elif [[ -n "$agent_ver" ]]; then
    live="$agent_ver"
  elif [[ -n "$flushed" ]]; then
    live="$flushed"
  elif [[ -n "$diag_ver" ]] && pb_ver_sort_ge "$diag_ver" "${PB_MIN_LIVE_VER:-0.2.51}"; then
    live="$diag_ver"
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
    PB_LIVE_VER=""
    PB_CLIENT_VER=""
    PB_RULES_VER="${PLATEBAND_LIVE_VER:-}"
    PB_FLUSH_LAG=unknown
    PB_AGENT_LOG=""
    PB_LAST_CARD=""
    PB_FEED_SOURCE=none
    PB_AGENT_SEQ=""
    return 1
  fi
  PB_FLUSHED_VER="$(pb_flushed_session_ver "$PB_SV")"
  PB_AGENT_LOG="$(pb_find_agent_live_log)"
  PB_AGENT_VER="$(pb_agent_live_ver "$PB_AGENT_LOG" 2>/dev/null || true)"
  PB_AGENT_SEQ="$(pb_sv_agent_seq "$PB_SV" 2>/dev/null || true)"
  PB_LAST_CARD="$(pb_last_diag_card "$PB_SV")"
  PB_DIAG_VER="$(pb_ver_from_card "$PB_LAST_CARD")"
  PB_CLIENT_VER="$(pb_client_ver "$PB_SV" "$PB_AGENT_LOG")"
  PB_LIVE_VER="$(pb_resolve_live_ver "$PB_CLIENT_VER" "$PB_FLUSHED_VER" "$PB_AGENT_VER" "$PB_DIAG_VER")"
  PB_RULES_VER="${PLATEBAND_LIVE_VER:-$PB_LIVE_VER}"
  PB_RUNTIME_FILE="$(pb_runtime_ver_log)"
  PB_RUNTIME_FILE_VER="$(pb_runtime_file_ver "$PB_RUNTIME_FILE" 2>/dev/null || true)"
  PB_FEED_SOURCE="sv_export"
  if [[ -f "$PB_RUNTIME_FILE" ]] && pb_runtime_file_fresh "$PB_RUNTIME_FILE" "$PB_SV"; then
    PB_FEED_SOURCE="runtime_ver_file"
  elif [[ -n "${PB_AGENT_LOG:-}" ]] && pb_agent_log_fresh "$PB_AGENT_LOG" "$PB_SV"; then
    PB_FEED_SOURCE="agent_live_file"
  fi

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
  PB_CHAT_LIVE=no
  if [[ -n "${PLATEBAND_LIVE_VER:-}" ]]; then
    PB_CHAT_LIVE=yes
  fi
  return 0
}

pb_live_ver_ok() {
  local live="$1" disk="$2" min="${3:-0.2.51}"
  pb_ver_sort_ge "$live" "$min"
}

pb_export_session_line() {
  printf 'live_ver=%s client_ver=%s flushed_session=%s deployed_ver=%s disk_ver=%s reload_pending=%s flush_lag=%s feed=%s runtime_file=%s agent_seq=%s rules_ver=%s chat_override=%s sv=%s' \
    "${PB_LIVE_VER:-?}" "${PB_CLIENT_VER:-?}" "${PB_FLUSHED_VER:-?}" "${PB_RUNTIME_VER:-?}" \
    "${PB_DISK_VER:-?}" "${PB_RELOAD_PENDING:-no}" "${PB_FLUSH_LAG:-?}" "${PB_FEED_SOURCE:-?}" \
    "${PB_RUNTIME_FILE_VER:-?}" "${PB_AGENT_SEQ:-?}" "${PB_RULES_VER:-?}" "${PB_CHAT_LIVE:-no}" "${PB_SV:-none}"
}

pb_best_card_lines() {
  local sv="$1" agent_log="$2" n="${3:-12}"
  if [[ -f "${agent_log:-}" ]]; then
    tail -"$n" "$agent_log" 2>/dev/null | grep -E 'PLATEBAND_CARD|PAINT ' || true
  fi
  rg 'PLATEBAND_CARD' "$sv" 2>/dev/null | tail -"$n" || true
}