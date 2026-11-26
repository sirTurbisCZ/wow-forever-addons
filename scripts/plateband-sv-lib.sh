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

pb_agent_live_export_path() {
  printf '%s' "$(pb_plateband_logs_dir)/agent-live-export.log"
}

pb_live_head_log_path() {
  printf '%s' "$(pb_plateband_logs_dir)/live-head.log"
}

# Client session ver from Logs/live-head.log (written on SESSION_START / CHAT_LOADED / AGENT_LIVE).
pb_read_live_head_file() {
  local f="${1:-$(pb_live_head_log_path)}"
  [[ -f "$f" ]] || return 1
  local line ver seq src load t
  line="$(head -1 "$f" 2>/dev/null || true)"
  [[ -n "$line" ]] || return 1
  ver="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  [[ -n "$ver" ]] || ver="$(sed -n 's/^live_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  seq="$(sed -n 's/.* seq=\([0-9]*\).*/\1/p' <<<"$line" | head -1)"
  src="$(sed -n 's/.* src=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  load="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  t="$(sed -n 's/.* t=\([0-9]*\).*/\1/p' <<<"$line" | head -1)"
  [[ -n "$ver" ]] || return 1
  PB_SESSION_LOAD="${load:-?}"
  printf '%s\t%s\t%s\t%s' "$ver" "${seq:-0}" "${src:-live_head}" "${t:-0}"
}

# Newest stamped ver= from a log body (CHAT_LOADED / RUNTIME_VER / SESSION_START / AGENT_LIVE).
pb_stamped_ver_from_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  python3 - "$f" <<'PY' 2>/dev/null || return 1
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
markers = (
    "CHAT_LOADED",
    "RUNTIME_VER",
    "SESSION_START",
    "PLATES_LOAD ok=1",
    "AGENT_LIVE",
)
best_t, best_ver, best_src = -1, None, None
pat = re.compile(r"\[(\d+)\][^\n]*")
for line in t.splitlines():
    if not any(m in line for m in markers):
        continue
    tm = pat.search(line)
    if not tm:
        continue
    ts = int(tm.group(1))
    vm = re.search(r"ver=([0-9.]+)", line)
    if not vm:
        continue
    src = "live_file"
    for m in ("CHAT_LOADED", "RUNTIME_VER", "SESSION_START", "PLATES_LOAD", "AGENT_LIVE"):
        if m in line:
            src = m.replace(" ok=1", "")
            break
    if ts >= best_t:
        best_t, best_ver, best_src = ts, vm.group(1), src
if best_ver:
    print("{}\t{}\t{}".format(best_ver, best_t, best_src))
PY
}

pb_live_feed_runtime() {
  local f line ver seq src pick_ts pick_ver pick_src pick_seq
  pick_ts=-1
  line="$(pb_read_live_head_file "$(pb_live_head_log_path)" 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    pick_ver="$(echo "$line" | cut -f1)"
    pick_ts="$(echo "$line" | cut -f4)"
    pick_src="live_head_file"
    [[ "$pick_ts" -ge 0 ]] || pick_ts="$(date +%s)"
  fi
  for f in "$(pb_runtime_ver_log)" "$(pb_agent_live_export_path)" "$(pb_repo_logs_dir)/agent-live-export.log" "$(pb_agent_live_log_path)"; do
    [[ -f "$f" ]] || continue
    if [[ "$f" == *runtime-ver.log ]]; then
      if ! pb_log_fresh_sec "$f" 600; then
        continue
      fi
      ver="$(pb_runtime_file_ver "$f" 2>/dev/null || true)"
      [[ -n "$ver" ]] || continue
      pick_ver="$ver"
      pick_src="runtime_ver_file"
      pick_ts="$(date +%s)"
      continue
    fi
    line="$(pb_stamped_ver_from_file "$f" 2>/dev/null || true)"
    [[ -n "$line" ]] || continue
    ver="$(echo "$line" | cut -f1)"
    local ts
    ts="$(echo "$line" | cut -f2)"
    src="$(echo "$line" | cut -f3)"
    [[ -n "$ver" && "$ts" -ge "$pick_ts" ]] || continue
    pick_ts="$ts"
    pick_ver="$ver"
    pick_src="$src"
  done
  [[ -n "${pick_ver:-}" ]] || return 1
  seq="0"
  printf '%s\t%s\t%s' "$pick_ver" "$seq" "$pick_src"
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

def table_at(name, key):
    m = re.search(rf'\["{name}"\]\s*=\s*\{{', t)
    if not m:
        return -1
    chunk = t[m.start() : m.start() + 600]
    am = re.search(rf'\["{key}"\]\s*=\s*(\d+)', chunk)
    return int(am.group(1)) if am else -1

cands = []

def add_cand(ts, v, src):
    if v and ts >= 0:
        cands.append((ts, v, src))

rv = table_ver("runtimeVer", "ver")
if rv:
    add_cand(table_at("runtimeVer", "at"), rv, "runtimeVer")

for needle, src in (
    ("CHAT_LOADED", "CHAT_LOADED"),
    ("RUNTIME_VER", "RUNTIME_VER"),
    ("SESSION_START", "SESSION_START"),
    ("PLATES_LOAD ok=1", "PLATES_LOAD"),
):
    at, cv, _ = newest_stamped(needle)
    if cv:
        add_cand(at, cv, src)

hm = re.search(r'\["liveHead"\]\s*=\s*"([^"]*)"', t)
if hm:
    blob = hm.group(1)
    vm = re.search(r"ver=([0-9.]+)", blob)
    am = re.search(r"at=([0-9]+)", blob)
    sm = re.search(r"seq=(\d+)", blob)
    if vm:
        lh_at = int(am.group(1)) if am else 0
        add_cand(lh_at, vm.group(1), "liveHead")
        if sm:
            seq = sm.group(1)

av = table_ver("agentLive", "ver")
if av:
    add_cand(table_at("agentLive", "at"), av, "agentLive")

ccv = re.search(r'\["configChatVer"\]\s*=\s*"([0-9.]+)"', t)
if ccv:
    add_cand(table_at("runtimeVer", "at"), ccv.group(1), "configChatVer")

ctm = re.search(r'\["chatTruthLine"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if ctm:
    cl = ctm.group(1).encode("utf-8").decode("unicode_escape")
    vm = re.search(r"(?:live_ver|plateband_ver)=([0-9.]+)", cl)
    tm = re.search(r"t=(\d+)", cl)
    cam = re.search(r'\["chatTruthAt"\]\s*=\s*(\d+)', t)
    ts = int(cam.group(1)) if cam else (int(tm.group(1)) if tm else 0)
    if vm:
        add_cand(ts, vm.group(1), "chatTruthLine")

if cands:
    cands.sort(key=lambda x: x[0])
    _, ver, source = cands[-1]

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
  local sv="$1" repo out ver seq src sm load
  repo="$(pb_repo_logs_dir)"
  mkdir -p "$repo"
  out="${repo}/live-head.txt"
  if pb_read_live_head_file "$(pb_live_head_log_path)" 2>/dev/null; then
    :
  elif [[ -f "$sv" ]]; then
    pb_client_ver "$sv" 2>/dev/null || true
  else
    return 1
  fi
  ver="$(pb_read_live_head_file "$(pb_live_head_log_path)" 2>/dev/null | cut -f1 || pb_client_ver "$sv" 2>/dev/null || true)"
  [[ -n "$ver" ]] || return 1
  seq="${PB_AGENT_SEQ:-0}"
  src="${PB_VER_SOURCE:-?}"
  load="${PB_SESSION_LOAD:-?}"
  sm="$(stat -f %m "$(pb_live_head_log_path)" 2>/dev/null || stat -c %Y "$(pb_live_head_log_path)" 2>/dev/null || echo 0)"
  [[ "$sm" -gt 0 ]] || sm="$(stat -f %m "$sv" 2>/dev/null || stat -c %Y "$sv" 2>/dev/null || echo 0)"
  printf 'live_ver=%s agent_seq=%s source=%s load=%s interface_ver=%s sv_mtime=%s feed=%s\n' \
    "$ver" "$seq" "$src" "$load" "$(pb_runtime_ver)" "$sm" "${PB_FEED_SOURCE:-live_head}" > "$out"
  PB_LIVE_HEAD="$out"
}

pb_sync_live_feed() {
  local sv="${1:-}"
  local repo mirror wow_exp repo_exp fel_head
  repo="$(pb_repo_logs_dir)"
  mkdir -p "$repo"
  PB_LIVE_SYNC="none"
  if [[ -x "$(pb_lib_root)/scripts/felog-sv-lib.sh" ]]; then
    if [[ "${FELIVE_HOST_PATCH:-0}" == "1" ]]; then
      pb_refresh_export_line1_from_toc 2 2>/dev/null || true
    fi
    pb_sync_export_l1_active "${PB_EXPORT_PROMOTE_MAX_AGE:-5}" 2>/dev/null || true
    # shellcheck source=scripts/felog-sv-lib.sh
    source "$(pb_lib_root)/scripts/felog-sv-lib.sh"
    felog_sync_repo_mirror 2>/dev/null || true
    local fel_head fel_bridge
    fel_head="$(felog_live_head_path)"
    fel_bridge="$(felog_bridge_head_path)"
    fel_agent="$(felog_agent_head_path)"
    if [[ -f "$fel_agent" ]]; then
      mkdir -p "$(dirname "$fel_head")"
      cp -f "$fel_agent" "$fel_head" 2>/dev/null || true
      cp -f "$fel_agent" "${repo}/agent-live-head.log" 2>/dev/null || true
      PB_LIVE_SYNC="agent_live_head"
    fi
    if [[ -f "$fel_bridge" && ( ! -f "$fel_head" || "$fel_bridge" -nt "$fel_head" ) ]]; then
      mkdir -p "$(dirname "$fel_head")"
      cp -f "$fel_bridge" "$fel_head" 2>/dev/null || true
    fi
  fel_pick="$(felog_pick_live_head_file 2>/dev/null || true)"
  if [[ -n "$fel_pick" && -f "$fel_pick" ]]; then
    cp -f "$fel_pick" "${repo}/felog-live-head.log" 2>/dev/null || true
    cp -f "$fel_pick" "$fel_head" 2>/dev/null || true
    PB_LIVE_SYNC="felog_live_head"
  fi
  fi
  local src
  src="$(pb_agent_live_log_path)"
  if [[ -f "$src" ]] && pb_log_fresh_sec "$src" 120; then
    tail -n 400 "$src" > "${repo}/agent-live.log" 2>/dev/null || true
    PB_LIVE_SYNC="agent_live"
  fi
  local wow_head repo_head
  wow_head="$(pb_live_head_log_path)"
  repo_head="${repo}/live-head-client.log"
  if [[ -f "$wow_head" ]]; then
    cp -f "$wow_head" "$repo_head" 2>/dev/null || true
    cp -f "$wow_head" "${repo}/live-head.log" 2>/dev/null || true
    PB_LIVE_SYNC="live_head_file"
  fi
  wow_exp="$(pb_agent_live_export_path)"
  repo_exp="${repo}/agent-live-export.log"
  if [[ -f "$wow_exp" ]]; then
    if [[ ! -f "$repo_exp" || "$wow_exp" -nt "$repo_exp" ]]; then
      cp -f "$wow_exp" "$repo_exp" 2>/dev/null || true
    fi
    PB_LIVE_SYNC="agent_live_export"
  fi
  local rv
  rv="$(pb_runtime_ver_log)"
  if [[ -f "$rv" ]] && pb_log_fresh_sec "$rv" 600; then
    cp -f "$rv" "${repo}/runtime-ver.log" 2>/dev/null || true
  fi
  if [[ -n "${sv:-}" && -f "$sv" ]]; then
    pb_write_wow_export_with_chat_truth "$sv" 2>/dev/null || true
    mirror="$repo_exp"
    local sv_ts wow_ts
    if [[ -f "$mirror" ]]; then
      wow_ts="$(pb_stamped_ver_from_file "$mirror" 2>/dev/null | cut -f2 || echo 0)"
    else
      wow_ts=0
    fi
    pb_mirror_sv_export "$sv" "${repo}/agent-live-sv-mirror.log" 2>/dev/null || true
    sv_ts="$(pb_stamped_ver_from_file "${repo}/agent-live-sv-mirror.log" 2>/dev/null | cut -f2 || echo 0)"
    if [[ "$sv_ts" -gt "$wow_ts" ]]; then
      if [[ -f "$wow_exp" ]] && pb_log_fresh_sec "$wow_exp" 20; then
        : # client export pulse is live — do not stomp with stale SV mirror
      else
        cp -f "${repo}/agent-live-sv-mirror.log" "$mirror" 2>/dev/null || true
        [[ "$PB_LIVE_SYNC" == "none" ]] && PB_LIVE_SYNC="sv_mirror"
      fi
    fi
    pb_publish_live_head "$sv" 2>/dev/null || true
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

pb_sv_chat_truth_ver() {
  local sv="$1"
  [[ -f "$sv" ]] || return 1
  python3 - "$sv" <<'PY' 2>/dev/null || true
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
m = re.search(r'\["chatTruthLine"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if not m:
    sys.exit(0)
cl = m.group(1).encode("utf-8").decode("unicode_escape")
vm = re.search(r"(?:live_ver|plateband_ver)=([0-9.]+)", cl)
if vm:
    print(vm.group(1))
PY
}

# One-line hint when Interface TOC ahead of in-session client (agent auto-sees TOC).
pb_reload_hint_if_needed() {
  [[ "${PB_RELOAD_PENDING:-no}" == yes && -n "${PB_RUNTIME_VER:-}" && -n "${PB_CLIENT_VER:-}" ]] || return 0
  echo "reload_hint: /reload — Plateband ${PB_RUNTIME_VER} on disk (session ${PB_CLIENT_VER})"
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

def unescape(s):
    try:
        return s.encode("utf-8").decode("unicode_escape")
    except Exception:
        return s

body = ""
em = re.search(r'\["export"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if em:
    body = unescape(em.group(1))
truth = ""
tm = re.search(r'\["chatTruthLine"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if tm:
    truth = unescape(tm.group(1)).strip()
if not truth:
    pb = re.search(r'Config\.VERSION = "([0-9.]+)"', pathlib.Path(src).read_text(errors="replace"))
    pass
if truth and body and not body.startswith("live_ver="):
    body = truth + "\n" + body
elif truth and not body:
    body = truth + "\n"
if not body:
    if re.search(r'\["agentLive"\]', t):
        body = "# sv_only mirror — no export blob yet\n"
        if truth:
            body = truth + "\n" + body
pathlib.Path(dst).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(dst).write_text(body[-48000:], encoding="utf-8")
PY
}

# Wow client export: ensure line 1 is live_ver= from SV chatTruthLine (io often sv_only).
pb_write_wow_export_with_chat_truth() {
  local sv="${1:-}"
  [[ -n "$sv" && -f "$sv" ]] || return 1
  local wow_exp
  wow_exp="$(pb_agent_live_export_path)"
  if [[ -f "$wow_exp" ]] && pb_log_fresh_sec "$wow_exp" 20; then
    return 0
  fi
  mkdir -p "$(dirname "$wow_exp")"
  pb_mirror_sv_export "$sv" "$wow_exp" 2>/dev/null || return 1
  return 0
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

# Live runtime — FElog live-head → Plateband live-head → export → SV.
pb_felog_live_head_path() {
  printf '%s' "$(pb_wow_root)/Interface/AddOns/ForeverErrorLog/Logs/live-head.log"
}

# Live runtime — SV export/unified → live-head (stale head ignored when SV newer).
pb_client_ver() {
  local sv="$1"
  local line v feed_ver feed_src feed_ts sv_ts unified uni_ver uni_ts truth_v head_v

  unified="$(pb_unified_runtime_from_sv "$sv" 2>/dev/null || true)"
  uni_ver="$(echo "$unified" | cut -f1)"
  if [[ -n "$uni_ver" ]]; then
    v="$uni_ver"
    PB_VER_SOURCE="$(echo "$unified" | cut -f3)"
    PB_AGENT_SEQ="$(echo "$unified" | cut -f2)"
  fi
  truth_v="$(pb_sv_chat_truth_ver "$sv" 2>/dev/null || true)"
  if [[ -n "$truth_v" ]] && { [[ -z "$v" ]] || pb_ver_sort_ge "$truth_v" "$v"; }; then
    v="$truth_v"
    PB_VER_SOURCE="chatTruthLine"
  fi

  line="$(pb_read_live_head_file "$(pb_felog_live_head_path)" 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    head_v="$(echo "$line" | cut -f1)"
    local pbv
    pbv="$(sed -n 's/.*plateband_ver=\([^ ]*\).*/\1/p' <(head -1 "$(pb_felog_live_head_path)" 2>/dev/null) 2>/dev/null || true)"
    [[ -n "$pbv" ]] && head_v="$pbv"
    if [[ -z "$v" ]] || pb_ver_sort_ge "$head_v" "$v"; then
      PB_VER_SOURCE="felog_live_head"
      PB_AGENT_SEQ="$(echo "$line" | cut -f2)"
      PB_SESSION_LOAD="$(echo "$line" | cut -f4)"
      v="$head_v"
    fi
    [[ -n "$v" ]] && printf '%s' "$v" && return 0
  fi
  line="$(pb_read_live_head_file "$(pb_live_head_log_path)" 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    head_v="$(echo "$line" | cut -f1)"
    if [[ -z "$v" ]] || pb_ver_sort_ge "$head_v" "$v"; then
      PB_VER_SOURCE="live_head_file"
      PB_AGENT_SEQ="$(echo "$line" | cut -f2)"
      v="$head_v"
    fi
    [[ -n "$v" ]] && printf '%s' "$v" && return 0
  fi
  line="$(pb_read_live_head_file "$(pb_repo_logs_dir)/live-head.log" 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    head_v="$(echo "$line" | cut -f1)"
    if [[ -z "$v" ]] || pb_ver_sort_ge "$head_v" "$v"; then
      PB_VER_SOURCE="live_head_mirror"
      PB_AGENT_SEQ="$(echo "$line" | cut -f2)"
      v="$head_v"
    fi
    [[ -n "$v" ]] && printf '%s' "$v" && return 0
  fi
  local wow_exp="${PB_AGENT_EXPORT:-}"
  [[ -n "$wow_exp" ]] || wow_exp="$(pb_agent_live_export_path)"
  if [[ -f "$wow_exp" ]] && pb_log_fresh_sec "$wow_exp" 300; then
    line="$(pb_stamped_ver_from_file "$wow_exp" 2>/dev/null || true)"
    feed_ver="$(echo "$line" | cut -f1)"
    feed_ts="$(echo "$line" | cut -f2)"
    feed_src="$(echo "$line" | cut -f3)"
  fi
  if [[ -z "$feed_ver" ]]; then
    line="$(pb_live_feed_runtime 2>/dev/null || true)"
    feed_ver="$(echo "$line" | cut -f1)"
    feed_src="$(echo "$line" | cut -f3)"
  fi
  line="$(pb_unified_runtime_from_sv "$sv" 2>/dev/null || true)"
  v="$(echo "$line" | cut -f1)"
  local sv_src
  sv_src="$(echo "$line" | cut -f3)"
  sv_ts="$(python3 - "$sv" <<'PY' 2>/dev/null || echo 0
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
best = -1
for m in re.finditer(r"\[(\d+)\][^\n\"]*(CHAT_LOADED|RUNTIME_VER|SESSION_START)", t):
    best = max(best, int(m.group(1)))
print(best if best >= 0 else 0)
PY
)"
  if [[ -n "$feed_ver" && ( -z "$v" || "${feed_ts:-0}" -ge "${sv_ts:-0}" ) ]]; then
    PB_VER_SOURCE="${feed_src:-live_feed}"
    PB_CLIENT_FEED_VER="$feed_ver"
    printf '%s' "$feed_ver"
    return 0
  fi
  if [[ -n "$v" ]]; then
    PB_VER_SOURCE="$sv_src"
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
  pb_sync_live_feed "$PB_SV" 2>/dev/null || true
  unified="$(pb_unified_runtime_from_sv "$PB_SV" 2>/dev/null || true)"
  PB_UNIFIED_VER="$(echo "$unified" | cut -f1)"
  PB_AGENT_SEQ="$(echo "$unified" | cut -f2)"
  PB_CLIENT_VER="$(pb_client_ver "$PB_SV")"
  PB_VER_SOURCE="${PB_VER_SOURCE:-$(echo "$unified" | cut -f3)}"
  PB_INTERFACE_VER="${PB_RUNTIME_VER:-}"
  PB_LIVE_VER="$(pb_resolve_live_ver "$PB_CLIENT_VER")"
  PB_RULES_VER="${PLATEBAND_LIVE_VER:-$PB_LIVE_VER}"
  PB_RUNTIME_FILE="$(pb_runtime_ver_log)"
  PB_RUNTIME_FILE_VER="$(pb_runtime_file_ver "$PB_RUNTIME_FILE" 2>/dev/null || true)"
  PB_FEED_SOURCE="sv_unified"
  if [[ "${PB_VER_SOURCE:-}" == live_head_file || "${PB_VER_SOURCE:-}" == live_head_mirror ]]; then
    PB_FEED_SOURCE="$PB_VER_SOURCE"
  fi
  local alf
  alf="$(pb_agent_live_log_path)"
  if [[ "$PB_FEED_SOURCE" == sv_unified ]] && pb_log_fresh_sec "$(pb_live_head_log_path)" 120 2>/dev/null; then
    PB_FEED_SOURCE="live_head_file"
  elif pb_log_fresh_sec "$alf" 120; then
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
    live_head_file|live_head_mirror|liveHead|liveHead_chat|CHAT_LOADED|RUNTIME_VER|SESSION_START|runtimeVer|runtime_ver_file|PLATES_LOAD|AGENT_LIVE)
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
  # In-session export can trail chatTruth until WTF flush; trust unified/export at Interface ver.
  if [[ "$PB_RELOAD_PENDING" == yes ]] && [[ -n "$PB_RUNTIME_VER" && -n "$PB_CLIENT_VER" ]] \
    && [[ "$PB_CLIENT_VER" == "$PB_RUNTIME_VER" ]]; then
    PB_RELOAD_PENDING=no
    PB_LIVE_VER="$PB_CLIENT_VER"
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
  printf 'live_ver=%s client_ver=%s session_load=%s interface_ver=%s ver_source=%s flushed_session=%s deployed_ver=%s disk_ver=%s reload_pending=%s flush_lag=%s feed=%s live_sync=%s runtime_file=%s agent_seq=%s rules_ver=%s chat_primary=%s sv=%s' \
    "${PB_LIVE_VER:-?}" "${PB_CLIENT_VER:-?}" "${PB_SESSION_LOAD:-?}" "${PB_INTERFACE_VER:-?}" "${PB_VER_SOURCE:-?}" "${PB_FLUSHED_VER:-?}" "${PB_RUNTIME_VER:-?}" \
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