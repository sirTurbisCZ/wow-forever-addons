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
pb_plateband_logs_dir() {
  printf '%s' "$(pb_wow_root)/Interface/AddOns/Plateband/Logs"
}

pb_felog_session_log() {
  local wow p
  wow="$(pb_wow_root)"
  p="${wow}/Interface/AddOns/ForeverErrorLog/Logs/session.log"
  if [[ -f "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  return 1
}

pb_find_felog_sv() {
  local wow f
  wow="$(pb_wow_root)"
  PB_FELOG_SV=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -z "$PB_FELOG_SV" || "$f" -nt "$PB_FELOG_SV" ]] && PB_FELOG_SV="$f"
  done < <(find "${wow}/WTF/Account" -name 'ForeverErrorLog.lua' -path '*/SavedVariables/*' 2>/dev/null)
  [[ -n "$PB_FELOG_SV" && -f "$PB_FELOG_SV" ]]
}

# Agent feed tail when session.log missing (Forever io=sv_only).
pb_mirror_felog_agent_sv() {
  local fel_sv="$1" out="$2"
  [[ -f "$fel_sv" && -n "$out" ]] || return 1
  python3 - "$fel_sv" "$out" <<'PY'
import re, pathlib, sys

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
t = src.read_text(errors="replace")

def unescape_lua_string(s):
    try:
        return s.encode("utf-8").decode("unicode_escape")
    except Exception:
        return s

body = ""
am = re.search(r'\["agentExport"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if am:
    body = unescape_lua_string(am.group(1))
if not body.strip():
    em = re.search(r'\["export"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
    if em:
        body = unescape_lua_string(em.group(1))

lines = [ln for ln in body.splitlines() if "AGENT[Plateband]" in ln]
if not lines:
    sys.exit(1)
dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text("\n".join(lines[-400:]) + "\n", encoding="utf-8")
PY
}

pb_felog_plateband_ver() {
  local f="$1" line v
  [[ -f "$f" ]] || return 1
  line="$(grep 'AGENT\[Plateband\]' "$f" 2>/dev/null | grep -E 'CHAT_LOADED|RUNTIME_VER|AGENT_LIVE|SESSION_START' | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*CHAT_LOADED ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  v="$(echo "$line" | sed -n 's/.*RUNTIME_VER ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  v="$(echo "$line" | sed -n 's/.*AGENT_LIVE ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  v="$(echo "$line" | sed -n 's/.*SESSION_START ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_sync_felog_plateband() {
  local repo fel out
  repo="$(pb_repo_logs_dir)"
  mkdir -p "$repo"
  out="${repo}/felog-plateband-live.log"
  fel="$(pb_felog_session_log 2>/dev/null || true)"
  if [[ -n "$fel" && -f "$fel" ]]; then
    grep 'AGENT\[Plateband\]' "$fel" 2>/dev/null | tail -400 > "$out" || true
    if [[ -s "$out" ]]; then
      PB_FELOG_SYNC="felog_bridge_file"
      return 0
    fi
  fi
  if pb_find_felog_sv; then
    if pb_mirror_felog_agent_sv "$PB_FELOG_SV" "$out" 2>/dev/null; then
      PB_FELOG_SYNC="felog_bridge_sv"
      return 0
    fi
  fi
  return 1
}

pb_repo_logs_dir() {
  printf '%s' "$(pb_lib_root)/addons/Plateband/Logs"
}

pb_agent_live_log_path() {
  printf '%s' "$(pb_plateband_logs_dir)/agent-live.log"
}

# Single runtime truth from SV — chat markers before SESSION; never PAINT/mirror files.
pb_unified_runtime_from_sv() {
  local sv="$1"
  [[ -f "$sv" ]] || return 1
  python3 - "$sv" <<'PY'
import re, pathlib, sys

def vtuple(s):
    return tuple(int(x) for x in s.split("."))

path = pathlib.Path(sys.argv[1])
t = path.read_text(errors="replace")
ver, source, seq = None, None, None

def table_ver(name, key):
    m = re.search(rf'\["{name}"\]\s*=\s*\{{', t)
    if not m:
        return None
    chunk = t[m.start() : m.start() + 600]
    vm = re.search(rf'\["{key}"\]\s*=\s*"([0-9.]+)"', chunk)
    if vm:
        return vm.group(1)
    vm = re.search(rf'\["{key}"\]\s*=\s*(\d+)', chunk)
    return vm.group(1) if vm else None

def export_last(needle):
    em = re.search(r'\["export"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
    if not em:
        return None
    body = em.group(1).encode("utf-8").decode("unicode_escape")
    hits = [ln for ln in body.split("\n") if needle in ln]
    return hits[-1] if hits else None

def newest_stamped(needle):
    best_t, best_ver, best_line = -1, None, None
    pat = re.compile(r"\[(\d+)\][^\n\"]*" + re.escape(needle))
    for m in pat.finditer(t):
        ts = int(m.group(1))
        line = m.group(0)
        vm = re.search(r"ver=([0-9.]+)", line)
        if vm and ts >= best_t:
            best_t, best_ver, best_line = ts, vm.group(1), line
    return best_t, best_ver, best_line

hm = re.search(r'\["liveHead"\]\s*=\s*"([^"]*)"', t)
lh_ver, lh_at, lh_seq, lh_chat = None, -1, None, False
if hm:
    blob = hm.group(1)
    vm = re.search(r"ver=([0-9.]+)", blob)
    am = re.search(r"at=([0-9]+)", blob)
    sm = re.search(r"seq=(\d+)", blob)
    lh_chat = "src=chat" in blob
    if vm:
        lh_ver = vm.group(1)
    if am:
        lh_at = int(am.group(1))
    if sm:
        lh_seq = sm.group(1)

chat_at, chat_ver, chat_line = newest_stamped("CHAT_LOADED")

# liveHead_chat wins unless a newer CHAT_LOADED line exists (post-reload truth).
if lh_chat and lh_ver:
    if chat_ver and chat_at > lh_at:
        ver, source = chat_ver, "CHAT_LOADED"
    else:
        ver, source = lh_ver, "liveHead_chat"
    if lh_seq:
        seq = lh_seq
elif chat_ver:
    ver, source = chat_ver, "CHAT_LOADED"
    sm = re.search(r"seq=(\d+)", chat_line or "")
    if sm:
        seq = sm.group(1)

if ver is None:
    last = export_last("RUNTIME_VER")
    if last:
        vm = re.search(r"ver=([0-9.]+)", last)
        if vm:
            ver, source = vm.group(1), "RUNTIME_VER"

if ver is None:
    tv = table_ver("runtimeVer", "ver")
    if tv:
        ver, source = tv, "runtimeVer"

if ver is None:
    _, rv, _ = newest_stamped("RUNTIME_VER")
    if rv:
        ver, source = rv, "RUNTIME_VER"

if ver is None and hm and lh_ver:
    ver, source = lh_ver, "liveHead"
    seq = lh_seq

if ver is None:
    tv = table_ver("agentLive", "ver")
    if tv:
        ver, source = tv, "agentLive"

# Never SESSION_START for live runtime when export is stale — seq only.
last = export_last("AGENT_LIVE")
if last:
    sm = re.search(r"seq=(\d+)", last)
    if sm:
        seq = sm.group(1)

if seq is None:
    sq = table_ver("agentLive", "seq")
    if sq:
        seq = sq
if seq is None:
    last = export_last("AGENT_LIVE")
    if last:
        sm = re.search(r"seq=(\d+)", last)
        if sm:
            seq = sm.group(1)

if ver:
    print("{}\t{}\t{}".format(ver, seq or "0", source or "?"))
PY
}

pb_publish_live_head() {
  local sv="$1" repo out ver seq src sm
  [[ -f "$sv" ]] || return 1
  repo="$(pb_repo_logs_dir)"
  mkdir -p "$repo"
  out="${repo}/live-head.txt"
  local line
  line="$(pb_unified_runtime_from_sv "$sv" 2>/dev/null || true)"
  [[ -n "$line" ]] || return 1
  ver="$(echo "$line" | cut -f1)"
  seq="$(echo "$line" | cut -f2)"
  src="$(echo "$line" | cut -f3)"
  sm="$(stat -f %m "$sv" 2>/dev/null || stat -c %Y "$sv" 2>/dev/null || echo 0)"
  printf 'live_ver=%s agent_seq=%s source=%s sv_mtime=%s feed=sv_live\n' \
    "$ver" "$seq" "$src" "$sm" > "$out"
  PB_LIVE_HEAD="$out"
}

pb_sync_live_feed() {
  local sv="${1:-}"
  local repo mirror
  repo="$(pb_repo_logs_dir)"
  mkdir -p "$repo"
  PB_LIVE_SYNC="none"
  local src
  src="$(pb_agent_live_log_path)"
  if [[ -f "$src" ]] && pb_log_fresh_sec "$src" 120; then
    tail -n 400 "$src" > "${repo}/agent-live.log" 2>/dev/null || true
    PB_LIVE_SYNC="agent_live"
  fi
  if [[ -n "${sv:-}" && -f "$sv" ]]; then
    mirror="${repo}/agent-live-export.log"
    pb_mirror_sv_export "$sv" "$mirror" 2>/dev/null || true
    pb_publish_live_head "$sv" 2>/dev/null || true
    [[ "$PB_LIVE_SYNC" == "none" ]] && PB_LIVE_SYNC="sv_mirror"
  fi
  pb_sync_felog_plateband 2>/dev/null || true
  if [[ "${PB_FELOG_SYNC:-}" == felog_bridge_* ]]; then
    [[ "$PB_LIVE_SYNC" == "none" ]] && PB_LIVE_SYNC="${PB_FELOG_SYNC}"
  fi
}

pb_log_fresh_sec() {
  local f="$1" max="${2:-25}"
  [[ -f "$f" ]] || return 1
  local lm now
  lm="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  [[ "$((now - lm))" -le "$max" ]]
}

pb_agent_live_tail_ver() {
  local f="$1" line v
  [[ -f "$f" ]] || return 1
  line="$(grep -E 'AGENT_LIVE|CHAT_LOADED|RUNTIME_VER|SESSION_START' "$f" 2>/dev/null | tail -1 || true)"
  v="$(echo "$line" | sed -n 's/.*AGENT_LIVE ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  v="$(echo "$line" | sed -n 's/.*CHAT_LOADED ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  v="$(echo "$line" | sed -n 's/.*RUNTIME_VER ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && { printf '%s' "$v"; return 0; }
  v="$(echo "$line" | sed -n 's/.*SESSION_START ver=\([0-9.]*\).*/\1/p')"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_runtime_ver_log() {
  printf '%s' "$(pb_plateband_logs_dir)/runtime-ver.log"
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
  fel="$(pb_felog_session_log 2>/dev/null || true)"
  [[ -n "$fel" ]] && pick="$fel"
  for name in session.log agent-live.log runtime-ver.log; do
    while IFS= read -r f; do
      [[ -z "$pick" || "$f" -nt "$pick" ]] && pick="$f"
    done < <(find "${wow}" -name "$name" -path '*/ForeverErrorLog/Logs/*' 2>/dev/null)
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

# Live runtime — pb_unified_runtime_from_sv only (no felog/agent mirror overrides).
pb_client_ver() {
  local sv="$1"
  local line v
  line="$(pb_unified_runtime_from_sv "$sv" 2>/dev/null || true)"
  v="$(echo "$line" | cut -f1)"
  if [[ -n "$v" ]]; then
    printf '%s' "$v"
    return 0
  fi
  v="$(pb_flushed_session_ver "$sv")"
  [[ -n "$v" ]] && printf '%s' "$v"
}

pb_resolve_live_ver() {
  local client_ver="$1"
  printf '%s' "${client_ver:-}"
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
  PB_LAST_CARD="$(pb_last_diag_card "$PB_SV")"
  PB_DIAG_VER="$(pb_ver_from_card "$PB_LAST_CARD")"
  local unified
  unified="$(pb_unified_runtime_from_sv "$PB_SV" 2>/dev/null || true)"
  PB_VER_SOURCE="$(echo "$unified" | cut -f3)"
  PB_AGENT_SEQ="$(echo "$unified" | cut -f2)"
  pb_sync_live_feed "$PB_SV" 2>/dev/null || true
  PB_UNIFIED_VER="$(echo "$unified" | cut -f1)"
  PB_CLIENT_VER="$(pb_client_ver "$PB_SV")"
  PB_LIVE_VER="$(pb_resolve_live_ver "$PB_CLIENT_VER")"
  PB_RULES_VER="${PLATEBAND_LIVE_VER:-$PB_LIVE_VER}"
  PB_RUNTIME_FILE="$(pb_runtime_ver_log)"
  PB_RUNTIME_FILE_VER="$(pb_runtime_file_ver "$PB_RUNTIME_FILE" 2>/dev/null || true)"
  PB_FEED_SOURCE="sv_unified"
  local alf
  alf="$(pb_agent_live_log_path)"
  if pb_log_fresh_sec "$alf" 120; then
    PB_FEED_SOURCE="agent_live_file"
  elif [[ -f "$PB_RUNTIME_FILE" ]] && pb_runtime_file_fresh "$PB_RUNTIME_FILE" "$PB_SV"; then
    PB_FEED_SOURCE="runtime_ver_file"
  elif [[ "${PB_FELOG_SYNC:-}" == felog_bridge_* ]]; then
    PB_FEED_SOURCE="${PB_FELOG_SYNC}"
  elif [[ "${PB_LIVE_SYNC:-none}" != "none" ]]; then
    PB_FEED_SOURCE="$PB_LIVE_SYNC"
  fi

  PB_CHAT_PRIMARY=no
  case "${PB_VER_SOURCE:-}" in
    liveHead_chat|CHAT_LOADED)
      PB_CHAT_PRIMARY=yes
      ;;
  esac

  PB_RELOAD_PENDING=no
  if [[ -n "$PB_RUNTIME_VER" && -n "$PB_LIVE_VER" ]]; then
    if [[ "$PB_LIVE_VER" == "$PB_RUNTIME_VER" ]]; then
      PB_RELOAD_PENDING=no
    elif pb_ver_sort_ge "$PB_RUNTIME_VER" "$PB_LIVE_VER"; then
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
  if [[ "${PB_CHAT_PRIMARY:-}" == yes ]]; then
    PB_CHAT_LIVE=yes
  fi
  return 0
}

pb_live_ver_ok() {
  local live="$1" disk="$2" min="${3:-0.2.51}"
  pb_ver_sort_ge "$live" "$min"
}

pb_export_session_line() {
  printf 'live_ver=%s client_ver=%s ver_source=%s flushed_session=%s deployed_ver=%s disk_ver=%s reload_pending=%s flush_lag=%s feed=%s live_sync=%s runtime_file=%s agent_seq=%s rules_ver=%s chat_primary=%s sv=%s' \
    "${PB_LIVE_VER:-?}" "${PB_CLIENT_VER:-?}" "${PB_VER_SOURCE:-?}" "${PB_FLUSHED_VER:-?}" "${PB_RUNTIME_VER:-?}" \
    "${PB_DISK_VER:-?}" "${PB_RELOAD_PENDING:-no}" "${PB_FLUSH_LAG:-?}" "${PB_FEED_SOURCE:-?}" \
    "${PB_LIVE_SYNC:-none}" "${PB_RUNTIME_FILE_VER:-?}" "${PB_AGENT_SEQ:-?}" "${PB_RULES_VER:-?}" "${PB_CHAT_PRIMARY:-no}" "${PB_SV:-none}"
}

pb_best_card_lines() {
  local sv="$1" agent_log="$2" n="${3:-12}"
  if [[ -f "${agent_log:-}" ]]; then
    tail -"$n" "$agent_log" 2>/dev/null | grep -E 'PLATEBAND_CARD|PAINT ' || true
  fi
  rg 'PLATEBAND_CARD' "$sv" 2>/dev/null | tail -"$n" || true
}