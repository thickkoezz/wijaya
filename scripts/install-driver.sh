#!/usr/bin/env bash
#
# install-driver.sh — build lalu install ntfs-3g (FUSE-T) ke /usr/local.
# Prasyarat: Xcode CLT, Homebrew, FUSE-T, dan dependensi build.
#   brew install autoconf automake libtool pkgconf gettext
#   brew install --cask macos-fuse-t/homebrew-cask/fuse-t
#
# Jalankan:  bash scripts/install-driver.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="/usr/local"

echo "==> Wijaya NTFS driver installer (FUSE-T build)"

OUT=$(bash "$SCRIPT_DIR/build-driver.sh")
BIN=$(echo "$OUT" | sed -n 's/^WJ_BIN=//p')
DYL=$(echo "$OUT" | sed -n 's/^WJ_DYLIB=//p')
if [ -z "$BIN" ] || [ -z "$DYL" ] || [ ! -f "$BIN" ] || [ ! -f "$DYL" ]; then
  echo "ERROR: build driver gagal (artefak tidak ditemukan)." >&2
  exit 1
fi
DYLBASE=$(basename "$DYL")

echo "==> Install ke $PREFIX (minta password admin)"
sudo mkdir -p "$PREFIX/bin" "$PREFIX/lib"
sudo install -m 0755 "$BIN" "$PREFIX/bin/ntfs-3g"
sudo install -m 0644 "$DYL" "$PREFIX/lib/$DYLBASE"
sudo ln -sf "$DYLBASE" "$PREFIX/lib/libntfs-3g.dylib"

echo "==> Verifikasi linkage"
if otool -L "$PREFIX/bin/ntfs-3g" | grep -q libfuse-t; then
  echo "    OK: $PREFIX/bin/ntfs-3g tertaut ke libfuse-t"
else
  echo "    PERINGATAN: tidak menemukan libfuse-t pada linkage." >&2
fi
if otool -L "$PREFIX/bin/ntfs-3g" | grep -q "libfuse.2.dylib"; then
  echo "    PERINGATAN: binary masih tertaut macFUSE." >&2
fi

cat <<'EOF'

==> Selesai!

LANGKAH WAJIB BERIKUTNYA — beri izin Full Disk Access:
  System Settings -> Privacy & Security -> Full Disk Access
    [+] lalu tekan Cmd+Shift+G, tambahkan:
        /usr/local/bin/ntfs-3g
        /bin/bash
    ...dan aplikasi Wijaya (Wijaya.app).

Tanpa izin ini, mount gagal dengan "Operation not permitted"
(macOS memblokir akses /dev/disk lewat TCC, bahkan sebagai root).
EOF
