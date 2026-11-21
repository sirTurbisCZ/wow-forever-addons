#!/usr/bin/env bash
# Symlink addons/<Name> → WoW Forever Interface/AddOns/<Name>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
WOW_ADDONS="${WOW_FOREVER_ADDONS:-/Applications/World of Warcraft/_forever_/Interface/AddOns}"

if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <AddonFolderName>"
  echo "Example: $0 ForeverErrorLog"
  echo "Optional: WOW_FOREVER_ADDONS=/path/to/Interface/AddOns $0 ForeverErrorLog"
  exit 1
fi

SRC="$ROOT/addons/$NAME"
DST="$WOW_ADDONS/$NAME"

if [[ ! -d "$SRC" ]]; then
  echo "error: source not found: $SRC" >&2
  exit 1
fi

if [[ ! -d "$WOW_ADDONS" ]]; then
  echo "error: Forever AddOns folder not found: $WOW_ADDONS" >&2
  echo "Set WOW_FOREVER_ADDONS if your install is elsewhere." >&2
  exit 1
fi

if [[ -e "$DST" || -L "$DST" ]]; then
  if [[ -L "$DST" ]]; then
    current="$(readlink "$DST")"
    if [[ "$current" == "$SRC" ]]; then
      echo "already linked: $DST → $SRC"
      exit 0
    fi
    echo "replacing existing symlink $DST (was → $current)"
    rm "$DST"
  else
    echo "error: $DST exists and is not a symlink. Move/rename it first." >&2
    exit 1
  fi
fi

ln -s "$SRC" "$DST"
echo "linked: $DST → $SRC"
echo "Next: /reload in game. Enable at character select if needed."
