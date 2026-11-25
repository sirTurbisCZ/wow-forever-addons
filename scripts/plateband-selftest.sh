#!/usr/bin/env bash
# Plateband CI / agent selftest (no WoW client required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADDON="$ROOT/addons/Plateband"
PLATES="$ADDON/Modules/Plates.lua"
CONFIG="$ADDON/Config.lua"
TOC="$ADDON/Plateband.toc"
LOCALS_MAX="${PLATEBAND_LOCALS_MAX:-195}"

fail() { echo "SELFTEST FAIL: $*" >&2; exit 1; }
pass() { echo "SELFTEST OK: $*"; }

[[ -f "$PLATES" ]] || fail "missing Plates.lua"
[[ -f "$CONFIG" ]] || fail "missing Config.lua"

VER="$(rg -o 'Config\.VERSION = "([^"]+)"' "$CONFIG" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
TOC_VER="$(rg -o '## Version: (.+)' "$TOC" | awk '{print $3}')"
[[ "$VER" == "$TOC_VER" ]] || fail "version mismatch Config=$VER toc=$TOC_VER"

command -v luac >/dev/null || fail "luac not installed"
luac -p "$PLATES" || fail "luac syntax"

LOCALS="$(grep -c '^local ' "$PLATES" || true)"
[[ "$LOCALS" -le "$LOCALS_MAX" ]] || fail "chunk locals $LOCALS > budget $LOCALS_MAX"

rg -q 'AuraUnitForPlate' "$PLATES" || fail "missing AuraUnitForPlate"
rg -q 'PlateUsesFriendlyHarmfulFilter' "$PLATES" || fail "missing friendly harmful filter"
rg -q 'GapAuraLive' "$PLATES" || fail "missing GapAuraLive"

if awk '/ShouldUseTargetAuraSource = function/,/^end$/' "$PLATES" | rg -q 'lastTargetPlateUnit'; then
  fail "ShouldUseTargetAuraSource still binds lastTargetPlateUnit (mob bleed)"
fi

rg -q 'CollectPlateDebuffButtons' "$PLATES" || fail "missing CollectPlateDebuffButtons"
rg -q 'friendFilter' "$PLATES" || fail "missing friendFilter on debuff harvest"

if rg 'FilterPlateHarmfulButtons\(out' "$PLATES" >/dev/null 2>&1; then
  if ! rg -q 'friendFilter' "$PLATES"; then
    fail "global harmful filter without friend gate"
  fi
fi

[[ -f "$ROOT/scripts/plateband-sv-gate.sh" ]] || fail "missing plateband-sv-gate.sh"
bash "$ROOT/scripts/plateband-sv-gate.sh" --offline || fail "sv-gate offline checks"

pass "ver=$VER locals=$LOCALS/$LOCALS_MAX"