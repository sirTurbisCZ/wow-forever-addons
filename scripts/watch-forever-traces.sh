#!/usr/bin/env bash
# Scan Forever addon SavedVariables; alert heuristics + FElog ERROR dedupe.
# Usage:
#   ./scripts/watch-forever-traces.sh
#   ./scripts/watch-forever-traces.sh watch 8
set -euo pipefail

WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
MODE="${1:-scan}"
INTERVAL="${2:-10}"
STATE_FILE="${FOREVER_WATCH_STATE:-/tmp/forever-trace-watch.state}"
ALERT_LOG="${FOREVER_ALERT_LOG:-/tmp/forever-trace-alerts.log}"

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
}

felog_new_errors() {
  local fel="$1"
  [[ -f "$fel" ]] || return 0
  local blob
  blob="$(rg -o 'SESSION_START|ERROR \[' "$fel" 2>/dev/null | tail -20 | tr '\n' '|' || true)"
  blob="${blob}$(rg -n '\["msg"\].*Plateband|Plateband/' "$fel" 2>/dev/null | tail -5 | tr '\n' '|' || true)"
  local prev
  prev="$(state_get fel_hash)"
  if [[ -n "$blob" && "$blob" != "$prev" ]]; then
  if rg -q 'ERROR ' "$fel" 2>/dev/null || rg -q 'Plateband' "$fel" 2>/dev/null; then
      local last
      last=$(extract_tail "$fel" 'ERROR |Plateband' 5)
      if [[ -n "$last" ]]; then
        emit_alert "[ForeverErrorLog] new session/error — $fel"
        printf '%s\n' "$last"
        state_set fel_hash "$blob"
        return 1
      fi
    fi
    state_set fel_hash "$blob"
  fi
  return 0
}

alert_check() {
  local alerts=0
  local pb
  pb=$(pick_newest "Plateband" 2>/dev/null || true)
  if [[ -n "${pb:-}" && -f "$pb" ]]; then
    if rg -q 'ver=0\.1\.|PLATEBAND_CARD' "$pb" 2>/dev/null && ! rg -q 'PAINT ver=' "$pb" 2>/dev/null; then
      emit_alert "[Plateband] SV stale 0.1.x — need 0.2.11+ /reload"
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
    if ! felog_new_errors "$fel"; then
      alerts=$((alerts + 1))
    elif rg -q 'ERROR ' "$fel" 2>/dev/null; then
      local last
      last=$(extract_tail "$fel" 'ERROR ' 3)
      if [[ -n "$last" ]]; then
        emit_alert "[FElog] ERROR in SV (seen) — $fel"
        printf '%s\n' "$last"
        alerts=$((alerts + 1))
      fi
    fi
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

run_scan() {
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