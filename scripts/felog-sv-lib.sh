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

felog_interface_ver() {
  local wow cfg
  wow="$(felog_wow_root)"
  cfg="$wow/Interface/AddOns/ForeverErrorLog/Config.lua"
  if [[ -f "$cfg" ]]; then
    rg -o 'Config\.VERSION = "([^"]+)"' "$cfg" | sed 's/.*"\(.*\)".*/\1/' | head -1
    return 0
  fi
  rg -o 'Config\.VERSION = "([^"]+)"' "$(_felog_lib_root)/addons/ForeverErrorLog/Config.lua" | sed 's/.*"\(.*\)".*/\1/' | head -1
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

felog_agent_head_path() {
  printf '%s' "$(felog_wow_root)/Interface/AddOns/Plateband/Logs/agent-live-head.log"
}

felog_bridge_head_path() {
  printf '%s' "$(felog_wow_root)/Interface/AddOns/Plateband/Logs/felog-live-head.log"
}

felog_live_head_path() {
  printf '%s' "$(felog_logs_dir)/live-head.log"
}

# Line 1 of Plateband agent-live-export when client io only allows that filename.
felog_build_chat_truth_from_toc() {
  local pb fe now seq src load feed
  pb="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
  fe="$(felog_interface_ver 2>/dev/null || echo "?")"
  now="$(date +%s)"
  seq="${1:-0}"
  src="${2:-TOC_PULSE}"
  load="${3:-watch_sync}"
  feed="${4:-host_toc_pulse}"
  printf 'live_ver=%s plateband_ver=%s felog_ver=%s seq=%s src=%s load=%s t=%s feed=%s\n' \
    "$pb" "$pb" "$fe" "$seq" "$src" "$load" "$now" "$feed"
}

# Refresh export line 1 from Interface TOC when client pulse lags (io=sv_only or stale SV).
pb_refresh_export_line1_from_toc() {
  local exp pb fe line tail ver age fe_head max_age
  exp="$(felog_wow_root)/Interface/AddOns/Plateband/Logs/agent-live-export.log"
  pb="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
  fe="$(felog_interface_ver 2>/dev/null || echo "?")"
  max_age="${1:-2}"
  now="$(date +%s)"
  line="$(felog_build_chat_truth_from_toc 0 "TOC_PULSE" "watch_sync" "host_toc_pulse")"
  if [[ -f "$exp" ]]; then
    ver="$(head -1 "$exp" 2>/dev/null | sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p')"
    age="$(felog_head_age_sec "$exp" 2>/dev/null || echo 999)"
    fe_head="$(head -1 "$exp" 2>/dev/null | sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p')"
    if [[ "$ver" == "$pb" && "$fe_head" == "$fe" && "$age" -le "$max_age" ]]; then
      return 0
    fi
    tail="$(tail -n +2 "$exp" 2>/dev/null || true)"
  else
    tail=""
    mkdir -p "$(dirname "$exp")"
  fi
  if [[ -n "$tail" ]]; then
    printf '%s\n%s' "$line" "$tail" > "$exp"
  else
    printf '%s\n' "$line" > "$exp"
  fi
  felog_materialize_agent_live_head_from_export 2>/dev/null || true
  return 0
}

felog_materialize_agent_live_head_from_export() {
  local exp head line sv
  exp="$(felog_wow_root)/Interface/AddOns/Plateband/Logs/agent-live-export.log"
  head="$(felog_agent_head_path)"
  [[ -f "$exp" ]] || return 1
  line="$(head -1 "$exp" 2>/dev/null || true)"
  if [[ "$line" != live_ver=* ]]; then
    sv="$(find "$(felog_wow_root)/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' 2>/dev/null | head -1)"
    if [[ -n "$sv" && -f "$sv" ]]; then
      line="$(python3 - "$sv" <<'PY' 2>/dev/null || true
import re, pathlib, sys
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
m = re.search(r'\["chatTruthLine"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if m:
    print(m.group(1).encode("utf-8").decode("unicode_escape").strip())
PY
)"
    fi
  fi
  [[ "$line" == live_ver=* ]] || return 1
  mkdir -p "$(dirname "$head")"
  printf '%s\n' "$line" > "$head"
  mkdir -p "$(felog_logs_dir)"
  printf '%s\n' "$line" > "$(felog_live_head_path)"
  printf '%s' "$head"
}

felog_pick_live_head_file() {
  local a b c
  a="$(felog_agent_head_path)"
  b="$(felog_live_head_path)"
  c="$(felog_bridge_head_path)"
  for f in "$a" "$b" "$c"; do
    if [[ -f "$f" ]]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

felog_agent_export_path() {
  printf '%s' "$(felog_logs_dir)/agent-live-export.log"
}

felog_plateband_export_path() {
  printf '%s' "$(felog_wow_root)/Interface/AddOns/Plateband/Logs/agent-live-export.log"
}

felog_plateband_sv_path() {
  local wow pick f
  wow="$(felog_wow_root)"
  pick=""
  while IFS= read -r f; do
    [[ -z "$pick" || "$f" -nt "$pick" ]] && pick="$f"
  done < <(find "${wow}/WTF/Account" -name 'Plateband.lua' -path '*/SavedVariables/*' 2>/dev/null)
  [[ -n "$pick" ]] || return 1
  printf '%s' "$pick"
}

# Client ExportTruthTicker truth (preferred over host-patched disk).
felog_read_chat_truth_sv() {
  local sv line at age now pb fe seq src load feed
  sv="$(felog_plateband_sv_path 2>/dev/null || true)"
  [[ -n "$sv" && -f "$sv" ]] || return 1
  local out
  out="$(python3 - "$sv" <<'PY' 2>/dev/null || true
import re, pathlib, sys, time
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")

def unescape(s):
    try:
        return s.encode("utf-8").decode("unicode_escape")
    except Exception:
        return s

def grab(key, line, default="?"):
    m = re.search(r"(?:^|\\s)" + key + r"=([^\\s]+)", line)
    return m.group(1) if m else default

line = ""
m = re.search(r'\["chatTruthLine"\]\s*=\s*"((?:\\.|[^"\\])*)"', t, re.S)
if m:
    line = unescape(m.group(1)).strip()
if not line:
    sys.exit(1)
at = 0
am = re.search(r'\["chatTruthAt"\]\s*=\s*(\d+)', t)
if am:
    at = int(am.group(1))
tm = re.search(r"t=(\d+)", line)
ts = int(tm.group(1)) if tm else (at or 0)
age = (int(time.time()) - ts) if ts > 0 else 9999
if age < 0:
    age = 9999
print(
    "plateband_ver={pb} felog_ver={fe} seq={seq} src={src} load={load} feed={feed} age_sec={age} truth_src=sv_chat_truth line={line}".format(
        pb=grab("plateband_ver", line, grab("live_ver", line, "?")),
        fe=grab("felog_ver", line, "?"),
        seq=grab("seq", line, "0"),
        src=grab("src", line, "?"),
        load=grab("load", line, "?"),
        feed=grab("feed", line, "?"),
        age=age,
        line=line,
    )
)
PY
)"
  [[ -n "$out" ]] || return 1
  printf '%s\n' "$out"
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

# Age for L1: pb_bridge client pulses — trust file mtime (GetTime-anchored t= may lag host wall).
# Otherwise min(mtime, now − t=).
felog_head_age_sec() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local disk line t now logical feed src
  disk="$(felog_file_age_sec "$f" 2>/dev/null || echo 9999)"
  line="$(head -1 "$f" 2>/dev/null || true)"
  feed="$(sed -n 's/.* feed=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  src="$(sed -n 's/.* src=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  if [[ "$src" =~ ^(EXPORT_PULSE|CHAT_LOADED)$ ]]; then
    printf '%s' "$disk"
    return 0
  fi
  if [[ "$feed" == "pb_bridge" ]]; then
    printf '%s' "$disk"
    return 0
  fi
  t="$(sed -n 's/.*[^0-9]t=\([0-9][0-9]*\).*/\1/p' <<<"$line" | head -1)"
  now="$(date +%s)"
  logical="$disk"
  if [[ -n "$t" && "$t" -gt 0 ]]; then
    logical=$((now - t))
    [[ "$logical" -lt 0 ]] && logical="$disk"
    if [[ "$logical" -lt "$disk" ]]; then
      disk="$logical"
    fi
  fi
  printf '%s' "$disk"
}

felog_plateband_export_pulse_path() {
  printf '%s' "$(felog_wow_root)/Interface/AddOns/Plateband/Logs/export-pulse.log"
}

felog_restamp_line_t() {
  local line="$1" now="${2:-$(date +%s)}"
  python3 - "$line" "$now" <<'PY'
import re, sys
line, now = sys.argv[1], sys.argv[2]
if re.search(r"\bt=\d+\b", line):
    print(re.sub(r"(t=)(\d+)", r"\g<1>" + now, line, count=1))
else:
    print(line.rstrip() + " t=" + now)
PY
}

felog_line_t_age_sec() {
  local line="$1"
  local t now
  t="$(sed -n 's/.*[^0-9]t=\([0-9][0-9]*\).*/\1/p' <<<"$line" | head -1)"
  [[ -n "$t" && "$t" -gt 0 ]] || return 1
  now="$(date +%s)"
  echo $((now - t))
}

# Active client export (mtime fresh): refresh host-wall t= only on client load= lines.
pb_touch_export_l1_timestamp() {
  local max_mtime="${1:-5}"
  local exp line disk_age src pb fe live fe_l now load
  exp="$(felog_plateband_export_path)"
  [[ -f "$exp" ]] || return 1
  disk_age="$(felog_file_age_sec "$exp" 2>/dev/null || echo 9999)"
  [[ "$disk_age" -le "$max_mtime" ]] || return 1
  line="$(head -1 "$exp" 2>/dev/null | tr -d '\r' || true)"
  [[ "$line" == live_ver=* ]] || return 1
  felog_export_l1_is_client_pulse "$line" || return 1
  src="$(sed -n 's/.* src=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  load="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  [[ "$src" =~ ^(EXPORT_PULSE|CHAT_LOADED)$ ]] || return 1
  [[ "$load" == "watch_sync" ]] && return 1
  pb="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
  fe="$(felog_interface_ver 2>/dev/null || echo "?")"
  live="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  fe_l="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  [[ "$live" == "$pb" && "$fe_l" == "$fe" ]] || return 1
  now="$(date +%s)"
  line="$(felog_restamp_line_t "$line" "$now")"
  mkdir -p "$(dirname "$exp")"
  printf '%s\n' "$line" > "$exp"
  felog_materialize_agent_live_head_from_export 2>/dev/null || true
  return 0
}

# Host bridge: promote freshest client append pulse to L1 when main w= rewrite stalls.
pb_promote_export_pulse_line() {
  local max_age="${1:-5}"
  local pulse exp line age pb fe now
  pulse="$(felog_plateband_export_pulse_path)"
  exp="$(felog_plateband_export_path)"
  [[ -f "$pulse" ]] || return 1
  age="$(felog_file_age_sec "$pulse" 2>/dev/null || echo 9999)"
  [[ "$age" -le "$max_age" ]] || return 1
  line="$(tail -1 "$pulse" 2>/dev/null | tr -d '\r' || true)"
  [[ "$line" == live_ver=* ]] || return 1
  pb="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
  fe="$(felog_interface_ver 2>/dev/null || echo "?")"
  local live fe_l
  live="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  fe_l="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  [[ "$live" == "$pb" && "$fe_l" == "$fe" ]] || return 1
  now="$(date +%s)"
  line="$(felog_restamp_line_t "$line" "$now")"
  mkdir -p "$(dirname "$exp")"
  printf '%s\n' "$line" > "$exp"
  felog_materialize_agent_live_head_from_export 2>/dev/null || true
  return 0
}

# True when L1 was written in-client (not host watch_sync / TOC patch).
felog_export_l1_is_client_pulse() {
  local line="$1"
  local src load feed
  src="$(sed -n 's/.* src=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  load="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  feed="$(sed -n 's/.* feed=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  [[ "$line" == live_ver=* ]] || return 1
  [[ "$feed" == "pb_bridge" ]] || return 1
  [[ "$load" == "watch_sync" || "$load" == "host_toc_pulse" || "$load" == "watch_sync" ]] && return 1
  [[ "$feed" == "host_toc_pulse" ]] && return 1
  if [[ "$src" == "EXPORT_PULSE" ]]; then
    [[ "$load" == "pulse" ]] && return 0
    return 1
  fi
  if [[ "$src" == "CHAT_LOADED" ]]; then
    [[ "$load" == "login" || "$load" == "reload" ]] && return 0
    return 1
  fi
  return 1
}

# Host watch: only when PB_HOST_EXPORT_SYNTH=1 — prove/gate must not use this path.
pb_restamp_export_l1_watch() {
  local exp line pb fe now live fe_l seq
  exp="$(felog_plateband_export_path)"
  pb="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
  fe="$(felog_interface_ver 2>/dev/null || echo "?")"
  [[ "$pb" != "?" && "$fe" != "?" ]] || return 1
  now="$(date +%s)"
  mkdir -p "$(dirname "$exp")"
  if [[ -f "$exp" ]]; then
    line="$(head -1 "$exp" 2>/dev/null | tr -d '\r' || true)"
    if [[ "$line" == live_ver=* ]]; then
      live="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
      fe_l="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
      if [[ "$live" == "$pb" && "$fe_l" == "$fe" ]]; then
        line="$(felog_restamp_line_t "$line" "$now")"
        printf '%s\n' "$line" >"$exp"
        felog_materialize_agent_live_head_from_export 2>/dev/null || true
        return 0
      fi
    fi
  fi
  seq="0"
  line="live_ver=${pb} plateband_ver=${pb} felog_ver=${fe} seq=${seq} src=EXPORT_PULSE load=watch_sync t=${now} feed=pb_bridge interface_pb=${pb} interface_fe=${fe} meta_pb=${pb} meta_fe=${fe}"
  printf '%s\n' "$line" >"$exp"
  felog_materialize_agent_live_head_from_export 2>/dev/null || true
  return 0
}

# Host assist: promote client export-pulse append only (never synth L1 for prove).
pb_sync_export_l1_active() {
  local max_age="${1:-5}"
  if pb_promote_export_pulse_line "$max_age" 2>/dev/null; then
    return 0
  fi
  if [[ "${PB_HOST_EXPORT_TOUCH:-0}" == "1" ]]; then
    pb_touch_export_l1_timestamp "$max_age" 2>/dev/null && return 0
  fi
  if [[ "${PB_HOST_EXPORT_SYNTH:-0}" == "1" ]]; then
    pb_restamp_export_l1_watch && return 0
  fi
  return 1
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
  local live pb fe seq src load feed age
  live="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  pb="$(sed -n 's/.*plateband_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  fe="$(sed -n 's/.*felog_ver=\([0-9.]*\).*/\1/p' <<<"$line" | head -1)"
  seq="$(sed -n 's/.* seq=\([0-9]*\).*/\1/p' <<<"$line" | head -1)"
  src="$(sed -n 's/.* src=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  load="$(sed -n 's/.* load=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  feed="$(sed -n 's/.* feed=\([^ ]*\).*/\1/p' <<<"$line" | head -1)"
  age="$(felog_head_age_sec "$f" 2>/dev/null || echo 9999)"
  [[ -n "$live" ]] || return 1
  printf 'live_ver=%s plateband_ver=%s felog_ver=%s seq=%s src=%s load=%s feed=%s age_sec=%s path=%s\n' \
    "$live" "${pb:-}" "${fe:-}" "${seq:-0}" "${src:-?}" "${load:-?}" "${feed:-?}" "$age" "$f"
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
  felog_materialize_agent_live_head_from_export 2>/dev/null || true
  local agent="$(felog_agent_head_path)"
  [[ -f "$agent" ]] && cp -f "$agent" "$(felog_logs_dir)/live-head.log" 2>/dev/null || true
  for name in live-head.log agent-live-export.log live-stream.log session.log; do
    local src="$repo/../../../Interface/AddOns/ForeverErrorLog/Logs/$name"
    src="$(felog_logs_dir)/$name"
    [[ -f "$src" ]] && cp -f "$src" "$repo/$name" 2>/dev/null || true
  done
}

felog_resolve_session_ver() {
  local head export line ver iface load pb sv_truth
  iface="$(felog_plateband_interface_ver 2>/dev/null || echo "?")"
  if sv_truth="$(felog_read_chat_truth_sv 2>/dev/null)"; then
    ver="$(echo "$sv_truth" | sed -n 's/.*plateband_ver=\([^ ]*\).*/\1/p')"
    [[ -n "$ver" ]] || ver="$(sed -n 's/.*live_ver=\([0-9.]*\).*/\1/p' <<<"$(echo "$sv_truth" | sed -n 's/.*line=//p')")"
    printf 'session_ver=%s interface_ver=%s source=sv_chat_truth age_sec=%s\n' \
      "$ver" "$iface" "$(echo "$sv_truth" | sed -n 's/.*age_sec=\([^ ]*\).*/\1/p')"
    return 0
  fi
  if head="$(felog_read_live_head 2>/dev/null)"; then
    load="$(sed -n 's/.*load=\([^ ]*\).*/\1/p' <<<"$head" | head -1)"
    # Reject host prove stubs — chat/TOC is ground truth; prove is not live.
    if [[ "$load" != "prove" ]]; then
      ver="$(sed -n 's/.*live_ver=\([^ ]*\).*/\1/p' <<<"$head")"
      pb="$(sed -n 's/.*plateband_ver=\([^ ]*\).*/\1/p' <<<"$head")"
      [[ -n "$pb" && "$pb" != "" ]] && ver="$pb"
      printf 'session_ver=%s interface_ver=%s source=live_head_file age_sec=%s\n' \
        "$ver" "$iface" "$(sed -n 's/.*age_sec=\([^ ]*\).*/\1/p' <<<"$head")"
      return 0
    fi
  fi
  line="$(felog_stamped_ver_from_export 2>/dev/null || true)"
  ver="$(echo "$line" | cut -f1)"
  if [[ -n "$ver" ]]; then
    age="$(felog_file_age_sec "$(felog_agent_export_path)" 2>/dev/null || echo "?")"
    printf 'session_ver=%s interface_ver=%s source=felog_agent_export age_sec=%s\n' "$ver" "$iface" "$age"
    return 0
  fi
  # Fall back to chat-truth TOC (never invent reload_pending from SV lag).
  printf 'session_ver=%s interface_ver=%s source=chat_truth_toc age_sec=?\n' "$iface" "$iface"
  return 0
}