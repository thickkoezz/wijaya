#!/usr/bin/env bash
#
# build-pkg.sh — bangun installer distribusi: Wijaya-<versi>.pkg dan .dmg
# Paket berisi: Wijaya.app (Release) + ntfs-3g (build FUSE-T) + libfuse-t runtime.
#
# Jalankan:  bash scripts/build-pkg.sh
#
# Catatan: paket TIDAK ditandatangani. Untuk distribusi luas, tambahkan
# Developer ID Installer + notarization.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION 2>/dev/null || echo 1.0)"
OUT="$ROOT/build/pkg"
PAYLOAD="$OUT/payload"
RESOURCES="$OUT/resources"

echo "==> Wijaya package builder — versi $VERSION"

command -v xcodegen >/dev/null 2>&1 || { echo "ERROR: butuh xcodegen (brew install xcodegen)" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$PAYLOAD" "$RESOURCES"

# --- Driver ntfs-3g (FUSE-T) ---------------------------------------------
DROUT=$(bash "$ROOT/scripts/build-driver.sh")
BIN=$(echo "$DROUT" | sed -n 's/^WJ_BIN=//p')
DYL=$(echo "$DROUT" | sed -n 's/^WJ_DYLIB=//p')
[ -f "$BIN" ] && [ -f "$DYL" ] || { echo "ERROR: build driver gagal" >&2; exit 1; }
DYLBASE=$(basename "$DYL")

# --- App (Release) -------------------------------------------------------
echo "==> Build Wijaya.app (Release)"
xcodegen generate >/dev/null
xcodebuild -project Wijaya.xcodeproj -scheme Wijaya -configuration Release \
  -derivedDataPath build build >/dev/null
APP="$ROOT/build/Build/Products/Release/Wijaya.app"
[ -d "$APP" ] || { echo "ERROR: $APP tidak ditemukan" >&2; exit 1; }

# --- Susun payload -------------------------------------------------------
echo "==> Susun payload"
mkdir -p "$PAYLOAD/Applications" "$PAYLOAD/usr/local/bin" "$PAYLOAD/usr/local/lib"
cp -R "$APP" "$PAYLOAD/Applications/Wijaya.app"
install -m 0755 "$BIN" "$PAYLOAD/usr/local/bin/ntfs-3g"
install -m 0644 "$DYL" "$PAYLOAD/usr/local/lib/$DYLBASE"
ln -sf "$DYLBASE" "$PAYLOAD/usr/local/lib/libntfs-3g.dylib"

# --- Resources installer -------------------------------------------------
cp "$ROOT/packaging/resources/welcome.html" "$RESOURCES/"
cp "$ROOT/packaging/resources/conclusion.html" "$RESOURCES/"
cp "$ROOT/LICENSE" "$RESOURCES/license.txt"

# --- Component pkg -------------------------------------------------------
echo "==> pkgbuild"
pkgbuild --root "$PAYLOAD" \
  --identifier dev.mieky.wijaya \
  --version "$VERSION" \
  --scripts "$ROOT/packaging/scripts" \
  --install-location / \
  "$OUT/Wijaya-component.pkg"

# --- Distribution pkg ----------------------------------------------------
echo "==> productbuild"
cat > "$OUT/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>Wijaya</title>
    <organization>dev.mieky</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <welcome file="welcome.html"/>
    <license file="license.txt"/>
    <conclusion file="conclusion.html"/>
    <choices-outline>
        <line choice="default"><line choice="dev.mieky.wijaya"/></line>
    </choices-outline>
    <choice id="default"/>
    <choice id="dev.mieky.wijaya" visible="false"><pkg-ref id="dev.mieky.wijaya"/></choice>
    <pkg-ref id="dev.mieky.wijaya" version="$VERSION" onConclusion="none">Wijaya-component.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild --distribution "$OUT/distribution.xml" \
  --resources "$RESOURCES" \
  --package-path "$OUT" \
  "$OUT/Wijaya-$VERSION.pkg"

# --- DMG -----------------------------------------------------------------
echo "==> dmg"
DMGSTAGE="$OUT/dmg"
mkdir -p "$DMGSTAGE"
cp "$OUT/Wijaya-$VERSION.pkg" "$DMGSTAGE/"
cat > "$DMGSTAGE/READ ME.txt" <<EOF
Wijaya $VERSION — NTFS baca-tulis untuk macOS

1. Prasyarat: pasang FUSE-T lebih dulu:
   brew install --cask macos-fuse-t/homebrew-cask/fuse-t

2. Pasang Wijaya:
   - Dobel-klik Wijaya-$VERSION.pkg, ATAU
   - Terminal:  sudo installer -pkg Wijaya-$VERSION.pkg -target / -allowUntrusted

3. WAJIB — beri Full Disk Access (sekali):
   System Settings -> Privacy & Security -> Full Disk Access, tambahkan:
     /usr/local/bin/ntfs-3g
     /bin/bash
     Wijaya.app
   (Installer sudah memasang helper privileged + aturan sudoers,
    jadi mount/unmount berjalan tanpa prompt password.)

4. Buka Wijaya -> klik "Mount Read-Write" pada disk NTFS.
   Selalu klik "Eject" sebelum mencabut disk.
EOF
hdiutil create -volname "Wijaya $VERSION" -srcfolder "$DMGSTAGE" \
  -ov -format UDZO "$OUT/Wijaya-$VERSION.dmg" >/dev/null

echo ""
echo "==> Selesai:"
ls -la "$OUT/Wijaya-$VERSION.pkg" "$OUT/Wijaya-$VERSION.dmg"
echo ""
echo "Catatan: paket belum ditandatangani. Instal lokal: 'open' paketnya (klik Install),"
echo "atau: sudo installer -pkg \"$OUT/Wijaya-$VERSION.pkg\" -target / -allowUntrusted"
