#!/usr/bin/env bash
# ForeverErrorLog live feed — file-first (no WTF flush).
set -euo pipefail

_felog_lib_root() {
  local d
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s' "$d"
}

felog_wow_root() {
  local r="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
  r="${r%/}"
  printf '%s' "$r"
}

felog_plateband_interface_ver() {
  local wow cfg
  wow="$(felog_wow_root)"
  cfg="$wow/Interface/AddOns/Plateband/Config.lua"
  if [[ -f "$cfg" ]]; then
    rg -o 'Config\.VERSION = "([^"]+)"' "$cfg" | sed 's/.*"\(.*\)".*/\1/' | head -1
    return 0
  fi
  rg -o 'Config\.VERSION = "([^"]+)"' "$(_felog_lib_root)/addons/Plateband/Config.lua" | sed 's/.*"\(.*\)".*/\1/' | head -1
}

felog_logs_dir() {
  printf '%s' "$(felog_wow_root)/Interface/AddOns/ForeverErrorLog/Logs"
}

felog_bridge_head_path() {
  printf '%s' "$(felog_wow_root)/Interface/AddOns/Plateband/Logs/felog-live-head.log"
}

felog_live_head_path() {
  printf '%s' "$(felog_logs_dir)/live-head.log"
}

felog_pick_live_head_file() {
  local a b
  a="$(felog_live_head_path)"
  b="$(felog_bridge_head_path)"
  if [[ -f "$a" ]] && felog_file_age_sec "$a" >/dev/null 2>&1; then
    printf '%s' "$a"
    return 0
  fi
  if [[ -f "$b" ]]; then
    printf '%s' "$b"
    return 0
  fi
  return 1
}

felog_agent_export_path() {
  printf '%s' "$(felog_logs_dir)/agent-live-export.log"
}

felog_live_stream_path() {
  printf '%s' "$(felog_logs_dir)/live-stream.log"
}

felog_session_log_path() {
  printf '%s' "$(felog_logs_dir)/session.log"
}

felog_file_age_sec() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local lm now
  lm="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  echo $((now - lm))
}

# Parse live-head.log one-liner (FElog 0.1.4+).
felog_read_live_head() {
  local f="${1:-}"
  if [[ -z "$f" ]]; then
    f="$(felog_pick_live_head_file 2>/dev/null || true)"
    [[ -n "$f" ]] || f="$(felog_live_head_path)"
  fi
  [[ -f "$f" ]] || return 1
  local line
  line="$(head -1 "$f" 2>/dev/null || true)"
  [[ -n "$line" ]] || return 1
  local live pb seq src load feed age
  live="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  pb="$(sed -n 's/.*plateband_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  seq="$(sed -n 's/.* seq=\([0-9]*\).*/\1/p' <<<"$line" | head -1)"
  src="$(sed -n 's/.* src=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  load="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  feed="$(sed -n 's/.* feed=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  age="$(felog_file_age_sec "$f" 2>/dev/null || echo 9999)"
  [[ -n "$live" ]] || return 1
  printf 'live_ver=%s plateband_ver=%s seq=%s src=%s load=%s feed=%s age_sec=%s path=%s\n' \
    "$live" "${pb:-}" "${seq:-0}" "${src:-?}" "${load:-?}" "${feed:-?}" "$age" "$f"
}

felog_stamped_ver_from_export() {
  local f="${1:-$(felog_agent_export_path)}"
  [[ -f "$f" ]] || return 1
  python3 - "$f" <<'PY' 2>/dev/null || return 1
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
best_t, best_ver, best_src = -1, None, None
pat = re.compile(r"\[(\d+)\][^\n]*")
for line in t.splitlines():
    if "AGENT[Plateband]" not in line and "CHAT_LOADED" not in line and "SESSION_START" not in line:
        continue
    pl = line.split("AGENT[Plateband]", 1)[-1] if "AGENT[Plateband]" in line else line
    if "CHAT_LOADED" not in pl and "SESSION_START" not in pl and "RUNTIME_VER" not in pl and "AGENT_LIVE" not in pl:
        continue
    tm = pat.search(line)
    if not tm:
        continue
    ts = int(tm.group(1))
    vm = re.search(r"ver=([0-9.]+)", pl)
    if vm and ts >= best_t:
        src = "export"
        if "CHAT_LOADED" in pl:
            src = "CHAT_LOADED"
        elif "SESSION_START" in pl:
            src = "SESSION_START"
        elif "AGENT_LIVE" in pl:
            src = "AGENT_LIVE"
        best_t, best_ver, best_src = ts, vm.group(1), src
if best_ver:
    print("{}\t{}\t{}".format(best_ver, best_t, best_src))
PY
}

felog_sync_repo_mirror() {
  local repo
  repo="$(_felog_lib_root)/addons/ForeverErrorLog/Logs"
  mkdir -p "$repo"
  for name in live-head.log agent-live-export.log live-stream.log session.log; do
    local src="$repo/../../../Interface/AddOns/ForeverErrorLog/Logs/$name"
    src="$(felog_logs_dir)/$name"
    [[ -f "$src" ]] && cp -f "$src" "$repo/$name" 2>/dev/null || true
  done
}

felog_resolve_session_ver() {
  local head export line ver iface
  iface="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
  if head="$(felog_read_live_head 2>/dev/null)"; then
    ver="$(sed -n 's/.*live_ver=\([^ ]*\).*/\1/p' <<<"$head")"
    pb="$(sed -n 's/.*plateband_ver=\([^ ]*\).*/\1/p' <<<"$head")"
    [[ -n "$pb" && "$pb" != "" ]] && ver="$pb"
    printf 'session_ver=%s interface_ver=%s source=live_head_file age_sec=%s\n' \
      "$ver" "$iface" "$(sed -n 's/.*age_sec=\([^ ]*\).*/\1/p' <<<"$head")"
    return 0
  fi
  line="$(felog_stamped_ver_from_export 2>/dev/null || true)"
  ver="$(echo "$line" | cut -f1)"
  if [[ -n "$ver" ]]; then
    age="$(felog_file_age_sec "$(felog_agent_export_path)" 2>/dev/null || echo "?")"
    printf 'session_ver=%s interface_ver=%s source=felog_agent_export age_sec=%s\n' "$ver" "$iface" "$age"
    return 0
  fi
  printf 'session_ver=? interface_ver=%s source=none age_sec=?\n' "$iface"
  return 1
}