#!/usr/bin/env bash
#
# build-icon.sh — hasilkan Sources/Resources/AppIcon.icns dari assets/AppIcon.svg.
# Butuh: rsvg-convert (brew install librsvg) + iconutil (bawaan macOS).
#
# Jalankan:  bash scripts/build-icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC="assets/AppIcon.svg"
OUT="Sources/Resources/AppIcon.icns"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

command -v rsvg-convert >/dev/null 2>&1 || {
  echo "ERROR: butuh rsvg-convert (brew install librsvg)" >&2; exit 1
}

render() { rsvg-convert -w "$1" -h "$1" "$SRC" -o "$2"; }

render 16   "$ICONSET/icon_16x16.png"
render 32   "$ICONSET/icon_16x16@2x.png"
render 32   "$ICONSET/icon_32x32.png"
render 64   "$ICONSET/icon_32x32@2x.png"
render 128  "$ICONSET/icon_128x128.png"
render 256  "$ICONSET/icon_128x128@2x.png"
render 256  "$ICONSET/icon_256x256.png"
render 512  "$ICONSET/icon_256x256@2x.png"
render 512  "$ICONSET/icon_512x512.png"
render 1024 "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$WORK"
echo "==> $OUT"
sips -g pixelWidth -g pixelHeight "$OUT" | tail -2
