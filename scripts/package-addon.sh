#!/usr/bin/env bash
# Build a Forever-distributable zip: <Addon>/<files> (GitHub Release layout).
# Usage:
#   ./scripts/package-addon.sh ForeverErrorLog
#   ./scripts/package-addon.sh ForeverErrorLog --out /tmp
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
OUT_DIR="$ROOT/dist"
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="${2:?}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <AddonFolderName> [--out DIR]"
  echo "Example: $0 ForeverErrorLog"
  exit 1
fi

SRC="$ROOT/addons/$NAME"
TOC="$SRC/$NAME.toc"
if [[ ! -d "$SRC" ]]; then
  echo "error: missing $SRC" >&2
  exit 1
fi
if [[ ! -f "$TOC" ]]; then
  echo "error: missing $TOC" >&2
  exit 1
fi

VER="$(grep -E '^## Version:' "$TOC" | head -1 | sed 's/^## Version:[[:space:]]*//;s/[[:space:]]*$//')"
if [[ -z "$VER" ]]; then
  echo "error: no ## Version in $TOC" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/package-${NAME}.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

DEST="$STAGE/$NAME"
mkdir -p "$DEST"

rsync -a \
  --exclude '_diag*' \
  --exclude '.reload*' \
  --exclude '*.bak*' \
  --exclude '.DS_Store' \
  --exclude '.git' \
  "$SRC/" "$DEST/"

missing=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^## ]] && continue
  file="${line//$'\r'/}"
  file="${file#"${file%%[![:space:]]*}"}"
  file="${file%"${file##*[![:space:]]}"}"
  [[ -z "$file" ]] && continue
  file="${file//\\//}"
  if [[ ! -f "$DEST/$file" ]]; then
    echo "error: TOC lists missing file: $file" >&2
    missing=1
  fi
done < "$TOC"
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

ZIP="$OUT_DIR/${NAME}-${VER}.zip"
rm -f "$ZIP"
(
  cd "$STAGE"
  zip -rq "$ZIP" "$NAME"
)

echo "packed: $ZIP"
echo "layout: ${NAME}/…  version=${VER}"
unzip -l "$ZIP" | head -40
