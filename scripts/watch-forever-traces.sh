#!/usr/bin/env bash
# Scan Forever addon SavedVariables + FElog live session.log (errors hit chat/SV line immediately in file).
# Usage:
#   ./scripts/watch-forever-traces.sh
#   ./scripts/watch-forever-traces.sh watch 3    # 2–5s recommended for FElog LIVE
set -euo pipefail

WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
MODE="${1:-scan}"
INTERVAL="${2:-3}"
STATE_FILE="${FOREVER_WATCH_STATE:-/tmp/forever-trace-watch.state}"
ALERT_LOG="${FOREVER_ALERT_LOG:-/tmp/forever-trace-alerts.log}"
COORD_INBOX="${FOREVER_COORDINATOR_INBOX:-/tmp/forever-trace-coordinator-inbox.txt}"

pick_newest() {
  local addon="$1"
  shopt -s nullglob
  local files=("${WOW_ROOT}/WTF/Account/"*/SavedVariables/"${addon}".lua)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    return 1
  fi
  local pick="${files[0]}"
  for f in "${files[@]}"; do
    if [[ "$f" -nt "$pick" ]]; then
      pick="$f"
    fi
  done
  printf '%s' "$pick"
}

pick_felog_session_log() {
  local p="${WOW_ROOT}/Interface/AddOns/ForeverErrorLog/Logs/session.log"
  if [[ -f "$p" ]]; then
    printf '%s' "$p"
    return 0
  fi
  local addon_src="${WOW_ROOT}/Interface/AddOns/ForeverErrorLog"
  if [[ -L "$addon_src" ]]; then
    local tgt
    tgt="$(readlink "$addon_src" 2>/dev/null || true)"
    if [[ -n "$tgt" && -f "$tgt/Logs/session.log" ]]; then
      printf '%s' "$tgt/Logs/session.log"
      return 0
    fi
  fi
  return 1
}

extract_tail() {
  local file="$1"
  local pattern="$2"
  local n="${3:-30}"
  if command -v rg >/dev/null 2>&1; then
    rg -n "$pattern" "$file" 2>/dev/null | tail -n "$n" || true
  else
    grep -E "$pattern" "$file" 2>/dev/null | tail -n "$n" || true
  fi
}

state_get() {
  local key="$1"
  if [[ -f "$STATE_FILE" ]]; then
    rg "^${key}=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true
  fi
}

state_set() {
  local key="$1"
  local val="$2"
  touch "$STATE_FILE"
  if rg -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    rg -v "^${key}=" "$STATE_FILE" >"$tmp" || true
    mv "$tmp" "$STATE_FILE"
  fi
  printf '%s=%s\n' "$key" "$val" >>"$STATE_FILE"
}

emit_alert() {
  local msg="$1"
  echo "ALERT $msg"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >>"$ALERT_LOG"
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$msg" >>"$COORD_INBOX"
}

felog_live_new_errors() {
  local log
  log=$(pick_felog_session_log 2>/dev/null || true)
  if [[ -z "${log:-}" || ! -f "$log" ]]; then
    return 0
  fi
  local size=0
  size=$(wc -c <"$log" | tr -d ' ')
  local prev
  prev="$(state_get fel_live_bytes)"
  prev="${prev:-0}"
  if [[ "$size" -le "$prev" ]]; then
    return 0
  fi
  local new_bytes=$((size - prev))
  local chunk
  chunk=$(tail -c "$new_bytes" "$log" 2>/dev/null || true)
  state_set fel_live_bytes "$size"
  if [[ -z "$chunk" ]]; then
    return 0
  fi
  if ! printf '%s' "$chunk" | rg -q 'ERROR'; then
    return 0
  fi
  if printf '%s' "$chunk" | rg -q 'Plateband'; then
    local last
    last=$(printf '%s' "$chunk" | rg 'ERROR.*Plateband|Plateband.*Plates\.lua' | tail -5 || true)
    emit_alert "[FElog LIVE] new Plateband ERROR — $log (chat+file; SV may lag until /reload)"
    if [[ -n "$last" ]]; then
      printf '%s\n' "$last"
    else
      printf '%s\n' "$chunk" | tail -8
    fi
    return 1
  fi
  if printf '%s' "$chunk" | rg -q 'ERROR'; then
    emit_alert "[FElog LIVE] new ERROR — $log"
    printf '%s\n' "$(printf '%s' "$chunk" | rg 'ERROR' | tail -3)"
    return 1
  fi
  return 0
}

felog_sv_new_errors() {
  local fel="$1"
  [[ -f "$fel" ]] || return 0
  local blob
  blob="$(rg -o 'SESSION_START|ERROR \[' "$fel" 2>/dev/null | tail -20 | tr '\n' '|' || true)"
  blob="${blob}$(rg -n '\["msg"\].*Plateband|Plateband/' "$fel" 2>/dev/null | tail -5 | tr '\n' '|' || true)"
  local prev
  prev="$(state_get fel_sv_hash)"
  if [[ -n "$blob" && "$blob" != "$prev" ]]; then
    if rg -q 'ERROR ' "$fel" 2>/dev/null; then
      local last
      last=$(extract_tail "$fel" 'ERROR .*Plateband|ERROR \[' 5)
      if [[ -n "$last" ]] && printf '%s' "$last" | rg -q 'Plateband'; then
        emit_alert "[FElog SV] new Plateband ERROR — $fel"
        printf '%s\n' "$last"
        state_set fel_sv_hash "$blob"
        return 1
      fi
    fi
    state_set fel_sv_hash "$blob"
  fi
  return 0
}

alert_check() {
  local alerts=0
  if ! felog_live_new_errors; then
    alerts=$((alerts + 1))
  fi

  local pb
  pb=$(pick_newest "Plateband" 2>/dev/null || true)
  if [[ -n "${pb:-}" && -f "$pb" ]]; then
    if rg -q 'SESSION_START ver=0\.2\.(10|11|12) ' "$pb" 2>/dev/null; then
      emit_alert "[Plateband] SV session < 0.2.13 — /reload on latest Plateband"
      alerts=$((alerts + 1))
    elif rg -q 'ver=0\.1\.|PLATEBAND_CARD' "$pb" 2>/dev/null && ! rg -q 'PAINT ver=' "$pb" 2>/dev/null; then
      emit_alert "[Plateband] SV stale 0.1.x — need 0.2.13+ /reload"
      alerts=$((alerts + 1))
    fi
    if rg -q 'PAINT .*tf=[1-9][0-9]* .*painted=0' "$pb" 2>/dev/null || \
       rg -q 'PAINT .*harv=[1-9][0-9]* .*painted=0' "$pb" 2>/dev/null; then
      emit_alert "[Plateband] TF/harv >0 painted=0 — $pb"
      alerts=$((alerts + 1))
    fi
  fi

  local bb
  bb=$(pick_newest "BetterBackpack" 2>/dev/null || true)
  if [[ -n "${bb:-}" && -f "$bb" ]]; then
    if rg -q 'ACTION.*MISMATCH=1' "$bb" 2>/dev/null || \
       rg -q 'ACTION BULK done.*queued=[1-9][0-9]* sold=0' "$bb" 2>/dev/null; then
      emit_alert "[BetterBackpack] bulk sold≠queued — $bb"
      alerts=$((alerts + 1))
    fi
  fi

  local fel
  fel=$(pick_newest "ForeverErrorLog" 2>/dev/null || true)
  if [[ -n "${fel:-}" && -f "$fel" ]]; then
  felog_sv_new_errors "$fel" || alerts=$((alerts + 1))
  fi
  return "$alerts"
}

dump_section() {
  local name="$1"
  local addon="$2"
  local pattern="$3"
  local file
  file=$(pick_newest "$addon" 2>/dev/null || true)
  if [[ -z "${file:-}" ]]; then
    echo "=== $name — (no SV file) ==="
    return
  fi
  echo "=== $name — $file ==="
  extract_tail "$file" "$pattern" 25
  echo
}

dump_live_felog() {
  local log
  log=$(pick_felog_session_log 2>/dev/null || true)
  if [[ -z "${log:-}" ]]; then
    echo "=== FElog LIVE — (no session.log under $WOW_ROOT; fileOk=no in SV) ==="
    echo
    return
  fi
  echo "=== FElog LIVE — $log ==="
  extract_tail "$log" 'SESSION_START|ERROR ' 20
  echo
}

run_scan() {
  dump_live_felog
  dump_section "Plateband" "Plateband" 'PAINT |PLATE |SESSION_START|PLATEBAND_CARD|ERROR '
  dump_section "BetterBackpack" "BetterBackpack" 'ACTION |BAGKEY |SESSION_START|ERROR '
  dump_section "ForeverErrorLog" "ForeverErrorLog" 'SESSION_START|ERROR |Plateband'
  echo "--- alerts ---"
  alert_check || true
}

if [[ "$MODE" == "watch" ]]; then
  while true; do
    clear 2>/dev/null || true
    date
    run_scan
    sleep "$INTERVAL"
  done
else
  run_scan
fi