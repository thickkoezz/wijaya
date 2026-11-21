#!/bin/bash
# wijaya-ntfsctl — helper root untuk Wijaya.
#
# Dipasang di /usr/local/libexec/wijaya-ntfsctl (root:wheel 0755) oleh aplikasi
# atau oleh installer .pkg, dengan aturan sudoers NOPASSWD yang hanya mengizinkan
# path ini. Aplikasi memanggilnya lewat `sudo -n` sehingga proses root adalah anak
# langsung Wijaya.app — atribusi TCC (Full Disk Access) menempel ke aplikasi.
#
# KEAMANAN: helper ini TIDAK menerima skrip arbitrer. Hanya subcommand tetap dengan
# argumen yang divalidasi. Jangan pernah menambah mode "jalankan apa saja".
set -u

LOG=/var/log/mount-ntfs-3g.log
OK=WIJAYA_OK
FAIL=WIJAYA_FAIL

is_dev()   { [[ "$1" =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; }
is_whole() { [[ "$1" =~ ^disk[0-9]+$ ]]; }
is_mp()    { [[ "$1" == /* && "$1" != "/" && "$1" != *..* ]]; }
is_exec()  { [[ "$1" == /* && -x "$1" ]]; }

usage() {
  cat >&2 <<'EOF'
usage:
  wijaya-ntfsctl mount {rw|ro} <dev> <whole> <mp> <volname> <ntfs3g> [--fuse-t <lib>] [--remove-hiberfile]
  wijaya-ntfsctl unmount <dev> <mp>
  wijaya-ntfsctl eject   <whole> <mp>
  wijaya-ntfsctl repair  <dev> <ntfsfix>
  wijaya-ntfsctl automount
EOF
}

do_mount() {
  local mode="${1:-}"; shift || true
  local dev="${1:-}"; shift || true
  local whole="${1:-}"; shift || true
  local mp="${1:-}"; shift || true
  local volname="${1:-}"; shift || true
  local ntfs3g="${1:-}"; shift || true

  local fuset="" remove_hiber=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --fuse-t) fuset="${2:-}"; shift 2 || true ;;
      --remove-hiberfile) remove_hiber=1; shift ;;
      *) echo "$FAIL"; echo "argumen mount tak dikenal: $1" >&2; exit 1 ;;
    esac
  done

  [ "$mode" = "rw" ] || [ "$mode" = "ro" ] || { echo "$FAIL"; echo "mode harus rw/ro" >&2; exit 1; }
  is_dev "$dev" || { echo "$FAIL"; echo "device tidak valid: $dev" >&2; exit 1; }
  is_whole "$whole" || { echo "$FAIL"; echo "whole disk tidak valid: $whole" >&2; exit 1; }
  is_mp "$mp" || { echo "$FAIL"; echo "mount point tidak valid: $mp" >&2; exit 1; }
  is_exec "$ntfs3g" || { echo "$FAIL"; echo "ntfs-3g tidak executable: $ntfs3g" >&2; exit 1; }
  if [ -n "$fuset" ]; then
    is_exec "$fuset" || { echo "$FAIL"; echo "libfuse-t tidak ada: $fuset" >&2; exit 1; }
  fi

  local boot_uid boot_gid
  boot_uid=$(/usr/bin/stat -f %u /dev/console 2>/dev/null || /usr/bin/id -u)
  boot_gid=$(/usr/bin/stat -f %g /dev/console 2>/dev/null || /usr/bin/id -g)

  local -a args=(
    -o "volname=$volname"
    -o local
    -o negative_vncache
    -o auto_xattr
    -o auto_cache
    -o noatime
    -o windows_names
    -o streams_interface=openxattr
    -o inherit
    -o "uid=$boot_uid"
    -o "gid=$boot_gid"
    -o allow_other
    -o big_writes
  )
  [ "$mode" = "ro" ] && args+=( -o ro )
  [ "$remove_hiber" = "1" ] && args+=( -o remove_hiberfile )

  /usr/sbin/diskutil unmountDisk force "$whole" >/dev/null 2>&1 \
    || /sbin/umount -f "$dev" >/dev/null 2>&1 || true
  /bin/mkdir -p "$mp"

  local rc=0
  if [ -n "$fuset" ]; then
    DYLD_INSERT_LIBRARIES="$fuset" DYLD_FORCE_FLAT_NAMESPACE=1 \
      "$ntfs3g" "${args[@]}" "$dev" "$mp" >> "$LOG" 2>&1 || rc=$?
  else
    "$ntfs3g" "${args[@]}" "$dev" "$mp" >> "$LOG" 2>&1 || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    echo "$FAIL"
    /usr/bin/tail -n 40 "$LOG" 2>/dev/null || true
    exit 1
  fi

  if [ "$mode" = "ro" ]; then
    /bin/ls "$mp" >/dev/null 2>&1 || { echo "$FAIL"; echo "verifikasi read-only gagal" >&2; exit 1; }
  else
    if ! { /usr/bin/touch "$mp/.wijaya_write_test" && /bin/rm -f "$mp/.wijaya_write_test"; }; then
      echo "$FAIL"; echo "verifikasi tulis gagal" >&2; exit 1
    fi
  fi

  echo "$OK"
}

do_unmount() {
  local dev="${1:-}"
  local mp="${2:-}"
  is_dev "$dev" || { echo "device tidak valid: $dev" >&2; exit 1; }
  is_mp "$mp" || { echo "mount point tidak valid: $mp" >&2; exit 1; }
  # FUSE-T mount via NFS tidak dikenali diskutil lewat device, jadi coba path juga.
  /usr/sbin/diskutil unmount force "$dev" 2>&1 \
    || /usr/sbin/diskutil unmount force "$mp" 2>&1 \
    || /sbin/umount "$mp" 2>&1 \
    || /sbin/umount -f "$mp" 2>&1
}

do_eject() {
  local whole="${1:-}"
  local mp="${2:-}"
  is_whole "$whole" || { echo "whole disk tidak valid: $whole" >&2; exit 1; }
  is_mp "$mp" || { echo "mount point tidak valid: $mp" >&2; exit 1; }
  /usr/sbin/diskutil unmount force "$mp" >/dev/null 2>&1 \
    || /sbin/umount -f "$mp" >/dev/null 2>&1 || true
  /usr/sbin/diskutil eject "$whole" 2>&1
}

do_repair() {
  local dev="${1:-}"
  local ntfsfix="${2:-}"
  is_dev "$dev" || { echo "device tidak valid: $dev" >&2; exit 1; }
  is_exec "$ntfsfix" || { echo "ntfsfix tidak executable: $ntfsfix" >&2; exit 1; }
  /usr/sbin/diskutil unmount force "$dev" >/dev/null 2>&1 || true
  "$ntfsfix" -d "$dev" 2>&1
}

# Auto-mount: dipanggil oleh LaunchAgent saat /Volumes berubah.
do_automount() {
  local ntfs3g=""
  for c in /usr/local/bin/ntfs-3g /opt/homebrew/bin/ntfs-3g; do
    [ -x "$c" ] && { ntfs3g="$c"; break; }
  done
  [ -n "$ntfs3g" ] || { /usr/bin/logger -t wijaya-automount "ntfs-3g tidak ditemukan"; exit 0; }

  local console_user owner u g
  console_user=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null) || exit 0
  { [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ "$console_user" != "loginwindow" ]; } || exit 0
  owner=$(/usr/bin/stat -f '%u:%g' "/Users/$console_user" 2>/dev/null) || exit 0
  u=${owner%%:*}; g=${owner##*:}

  # Beri waktu FSKit menyelesaikan mount read-only-nya sebelum kita ambil alih.
  local n=0
  while [ "$n" -lt 3 ]; do
    /sbin/mount | /usr/bin/grep -qE '\(ntfs,.*read-only|fskit' && break
    /bin/sleep 2; n=$((n+1))
  done

  local dev id info vol whole
  for dev in /dev/disk*s*; do
    [ -e "$dev" ] || continue
    id=${dev#/dev/}
    info=$(/usr/sbin/diskutil info "$dev" 2>/dev/null) || continue
    echo "$info" | /usr/bin/grep -q 'File System Personality:.*NTFS' || continue

    vol=$(echo "$info" | /usr/bin/awk -F': *' '/Volume Name/{print $2; exit}')
    [ -n "$vol" ] || continue

    /sbin/mount | /usr/bin/grep -qF "fuse-t:/$vol on " && continue

    whole=${id%s*}
    /usr/sbin/diskutil unmountDisk force "$whole" >/dev/null 2>&1 || true
    /bin/mkdir -p "/Volumes/$vol"

    if "$ntfs3g" \
        -o "volname=$vol" -o local -o negative_vncache -o auto_xattr -o auto_cache \
        -o noatime -o windows_names -o streams_interface=openxattr -o inherit \
        -o "uid=$u" -o "gid=$g" -o allow_other -o big_writes \
        "$dev" "/Volumes/$vol" >> "$LOG" 2>&1; then
      /usr/bin/logger -t wijaya-automount "$vol -> /Volumes/$vol read-write"
    else
      /usr/bin/logger -t wijaya-automount "gagal mount $vol (lihat $LOG)"
    fi
  done
  exit 0
}

cmd="${1:-}"
shift || true
case "$cmd" in
  mount)     do_mount "$@" ;;
  unmount)   do_unmount "$@" ;;
  eject)     do_eject "$@" ;;
  repair)    do_repair "$@" ;;
  automount) do_automount "$@" ;;
  ""|help|-h|--help) usage; exit 0 ;;
  *) usage; exit 1 ;;
esac
