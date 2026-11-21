#!/usr/bin/env bash
#
# build-driver.sh — build ntfs-3g (fork macos-fuse-t, tertaut libfuse-t).
# Tidak butuh root. Mencetak path artefak pada baris terakhir:
#   WJ_BIN=<path binary>
#   WJ_DYLIB=<path dylib>
#
# Dipakai oleh install-driver.sh dan build-pkg.sh.
set -euo pipefail

REPO_URL="https://github.com/macos-fuse-t/ntfs-3g"
BUILD_DIR="${TMPDIR:-/tmp}/wijaya-ntfs3g-build"

for tool in git make autoconf automake glibtoolize pkgconf; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' tidak ditemukan." >&2
    echo "  xcode-select --install && brew install autoconf automake libtool pkgconf gettext" >&2
    exit 1
  fi
done

if [ ! -e /usr/local/lib/libfuse-t.dylib ]; then
  echo "ERROR: FUSE-T tidak ditemukan (/usr/local/lib/libfuse-t.dylib)." >&2
  echo "  brew install --cask macos-fuse-t/homebrew-cask/fuse-t" >&2
  exit 1
fi

echo "==> Mengambil sumber ntfs-3g (macos-fuse-t fork)" >&2
rm -rf "$BUILD_DIR"
git clone --depth 1 "$REPO_URL" "$BUILD_DIR" >/dev/null 2>&1
cd "$BUILD_DIR"

echo "==> Menyiapkan build (autotools)" >&2
glibtoolize --force --copy >/dev/null 2>&1 || true
[ -f ../ltmain.sh ] && cp -f ../ltmain.sh .
autoreconf -fi >/dev/null 2>&1

echo "==> Configure (link ke libfuse-t)" >&2
export CPPFLAGS="-I/usr/local/include/fuse"
export LDFLAGS="-L/usr/local/lib -lfuse-t -Wl,-rpath,/usr/local/lib"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$(brew --prefix 2>/dev/null || echo /opt/homebrew)/lib/pkgconfig"
./configure --prefix=/usr/local --with-fuse=external \
  --sbindir=/usr/local/bin --bindir=/usr/local/bin >/dev/null

echo "==> Build" >&2
make -j"$(sysctl -n hw.ncpu)" >/dev/null

DYL_REL=$(ls libntfs-3g/.libs/libntfs-3g.*.dylib | head -1)
echo "WJ_BIN=$BUILD_DIR/src/.libs/ntfs-3g"
echo "WJ_DYLIB=$BUILD_DIR/$DYL_REL"
