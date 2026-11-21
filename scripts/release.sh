#!/usr/bin/env bash
#
# release.sh — bangun paket rilis lalu cetak sha256 + potongan cask.
# Jalur distribusi GRATIS (tanpa Developer ID / notarization Apple).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION)"
bash "$ROOT/scripts/build-pkg.sh"

PKG="$ROOT/build/pkg/Wijaya-$VERSION.pkg"
DMG="$ROOT/build/pkg/Wijaya-$VERSION.dmg"
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

cat <<EOF

============================================================
 Siap diunggah ke GitHub Releases (tag v$VERSION):
   $PKG
   $DMG
============================================================

sha256 (dmg): $SHA

Isi ke Casks/wijaya.rb:
   version "$VERSION"
   sha256 "$SHA"

Pengguna bisa memasang tanpa peringatan Gatekeeper lewat:
   brew install --cask wijaya

Atau manual (unsigned):
   xattr -dr com.apple.quarantine ~/Downloads/Wijaya-$VERSION.dmg
   open ~/Downloads/Wijaya-$VERSION.dmg   # lalu klik Install
EOF
