#!/usr/bin/env bash
# Scan Forever addon silent traces in SavedVariables; optional watch loop + alerts.
# Usage:
#   ./scripts/watch-forever-traces.sh           # one-shot
#   ./scripts/watch-forever-traces.sh watch 8 # poll every 8s
#   WOW_FOREVER_ROOT=/path ./_scripts/watch-forever-traces.sh
set -euo pipefail

WOW_ROOT="${WOW_FOREVER_ROOT:-/Applications/World of Warcraft/_forever_}"
MODE="${1:-scan}"
INTERVAL="${2:-10}"

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

alert_check() {
  local alerts=0
  local pb
  pb=$(pick_newest "Plateband" 2>/dev/null || true)
  if [[ -n "${pb:-}" && -f "$pb" ]]; then
    if rg -q 'ver=0\.1\.|PLATEBAND_CARD' "$pb" 2>/dev/null && ! rg -q 'PAINT ver=' "$pb" 2>/dev/null; then
      echo "ALERT [Plateband] live SV still 0.1.x card trace — install 0.2.10+ (pb branch) + /reload"
      alerts=$((alerts + 1))
    fi
    if rg -q 'PAINT .*tf=[1-9][0-9]* .*painted=0' "$pb" 2>/dev/null || \
       rg -q 'PAINT .*harv=[1-9][0-9]* .*painted=0' "$pb" 2>/dev/null; then
      echo "ALERT [Plateband] TF/harv >0 but painted=0 — see PAINT lines in $pb"
      alerts=$((alerts + 1))
    fi
  fi

  local bb
  bb=$(pick_newest "BetterBackpack" 2>/dev/null || true)
  if [[ -n "${bb:-}" && -f "$bb" ]]; then
    if rg -q 'ACTION.*MISMATCH=1' "$bb" 2>/dev/null || \
       rg -q 'ACTION BULK done.*queued=([1-9][0-9]*) sold=0' "$bb" 2>/dev/null; then
      echo "ALERT [BetterBackpack] bulk sell sold≠queued — see ACTION in $bb"
      alerts=$((alerts + 1))
    fi
  fi

  local fel
  fel=$(pick_newest "ForeverErrorLog" 2>/dev/null || true)
  if [[ -n "${fel:-}" && -f "$fel" ]]; then
    if rg -q 'ERROR ' "$fel" 2>/dev/null; then
      local last
      last=$(extract_tail "$fel" 'ERROR ' 3)
      if [[ -n "$last" ]]; then
        echo "ALERT [FElog] recent ERROR in session — $fel"
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
  dump_section "Plateband" "Plateband" 'PAINT |PLATE |SESSION_START|PLATEBAND_CARD'
  dump_section "BetterBackpack" "BetterBackpack" 'ACTION |BAGKEY |SESSION_START|ERROR '
  dump_section "ForeverErrorLog" "ForeverErrorLog" 'SESSION_START|ERROR |INFO '
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