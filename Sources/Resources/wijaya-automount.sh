#!/bin/bash
# Wijaya auto-mount — mount NTFS read-write via ntfs-3g (build FUSE-T).
# Dipanggil oleh LaunchAgent "com.mieky.wijaya.automount" lewat `sudo -n`.
# Berjalan sebagai root tetapi di dalam konteks sesi user.
set -u

TAG=wijaya-automount
NTFS3G=/usr/local/bin/ntfs-3g
LOG=/var/log/mount-ntfs-3g.log

[ -x "$NTFS3G" ] || { /usr/bin/logger -t "$TAG" "ntfs-3g tidak ditemukan di $NTFS3G"; exit 0; }

CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null) || exit 0
{ [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ] && [ "$CONSOLE_USER" != "loginwindow" ]; } || exit 0
OWNER=$(/usr/bin/stat -f '%u:%g' "/Users/$CONSOLE_USER" 2>/dev/null) || exit 0
U=${OWNER%%:*}; G=${OWNER##*:}

# Beri waktu FSKit menyelesaikan mount read-only-nya sebelum kita ambil alih.
n=0
while [ "$n" -lt 3 ]; do
  /sbin/mount | /usr/bin/grep -qE '\(ntfs,.*read-only|fskit' && break
  /bin/sleep 2; n=$((n+1))
done

for dev in /dev/disk*s*; do
  [ -e "$dev" ] || continue
  id=${dev#/dev/}
  info=$(/usr/sbin/diskutil info "$dev" 2>/dev/null) || continue
  echo "$info" | /usr/bin/grep -q 'File System Personality:.*NTFS' || continue

  vol=$(echo "$info" | /usr/bin/awk -F': *' '/Volume Name/{print $2; exit}')
  [ -n "$vol" ] || continue

  # Sudah kita mount read-write? beres.
  if /sbin/mount | /usr/bin/grep -qF "fuse-t:/$vol on "; then
    continue
  fi

  whole=${id%s*}

  /usr/sbin/diskutil unmountDisk force "$whole" >/dev/null 2>&1 || true
  /bin/mkdir -p "/Volumes/$vol"

  if "$NTFS3G" \
      -o volname="$vol" -o local -o negative_vncache -o auto_xattr -o auto_cache \
      -o noatime -o windows_names -o streams_interface=openxattr -o inherit \
      -o uid="$U" -o gid="$G" -o allow_other -o big_writes \
      "$dev" "/Volumes/$vol" >> "$LOG" 2>&1; then
    /usr/bin/logger -t "$TAG" "$vol -> /Volumes/$vol read-write"
  else
    /usr/bin/logger -t "$TAG" "gagal mount $vol (lihat $LOG)"
  fi
done

exit 0
