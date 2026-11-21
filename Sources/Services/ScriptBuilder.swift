import Foundation

/// Membangun skrip shell yang dijalankan sebagai root.
///
/// PENTING (keamanan): skrip ini berjalan sebagai root. Semua nilai dinamis
/// (nama volume, path) HARUS di-quote dengan `shellQuote` agar tidak bisa
/// menyuntikkan perintah. Jangan pernah interpolasi mentah.
enum ScriptBuilder {

    // MARK: - Validasi

    static let deviceNodePattern = #"^/dev/disk[0-9]+s[0-9]+$"#
    static let wholeDiskPattern = #"^disk[0-9]+$"#

    static func isValidDeviceNode(_ value: String) -> Bool {
        value.range(of: deviceNodePattern, options: .regularExpression) != nil
    }

    static func isValidWholeDisk(_ value: String) -> Bool {
        value.range(of: wholeDiskPattern, options: .regularExpression) != nil
    }

    // MARK: - Shell quoting

    /// Membungkus nilai dalam single quotes dan meng-escape single quote internal.
    /// Contoh: `My Passport` -> `'My Passport'`; `a'b` -> `'a'\''b'`.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Marker output

    static let okMarker = "WIJAYA_OK"
    static let failMarker = "WIJAYA_FAIL"

    // MARK: - Perintah

    static func mountReadWrite(
        volume: Volume,
        ntfs3gPath: String,
        mountPoint: String,
        backend: FuseBackend = .macFUSE,
        fuseTLibraryPath: String? = nil,
        removeHiberfile: Bool = false
    ) -> String {
        mount(
            volume: volume,
            ntfs3gPath: ntfs3gPath,
            mountPoint: mountPoint,
            backend: backend,
            fuseTLibraryPath: fuseTLibraryPath,
            readOnly: false,
            removeHiberfile: removeHiberfile
        )
    }

    static func mountReadOnly(
        volume: Volume,
        ntfs3gPath: String,
        mountPoint: String,
        backend: FuseBackend = .macFUSE,
        fuseTLibraryPath: String? = nil
    ) -> String {
        mount(
            volume: volume,
            ntfs3gPath: ntfs3gPath,
            mountPoint: mountPoint,
            backend: backend,
            fuseTLibraryPath: fuseTLibraryPath,
            readOnly: true,
            removeHiberfile: false
        )
    }

    private static func mount(
        volume: Volume,
        ntfs3gPath: String,
        mountPoint: String,
        backend: FuseBackend,
        fuseTLibraryPath: String?,
        readOnly: Bool,
        removeHiberfile: Bool
    ) -> String {
        let device = shellQuote(volume.deviceNode)
        let wholeDisk = shellQuote(volume.wholeDisk)
        let target = shellQuote(mountPoint)
        let volName = shellQuote(volume.volumeName)
        let tool = shellQuote(ntfs3gPath)

        let runner: String
        if backend == .fuseT, let library = fuseTLibraryPath {
            // FUSE-T: kext-less. Interpose libfuse-t di atas libfuse macFUSE.
            runner = "DYLD_INSERT_LIBRARIES=\(shellQuote(library)) DYLD_FORCE_FLAT_NAMESPACE=1 \(tool)"
        } else {
            runner = tool
        }

        var options = [
            "-o volname=\(volName)",
            "-o local",
            "-o negative_vncache",
            "-o auto_xattr",
            "-o auto_cache",
            "-o noatime",
            "-o windows_names",
            "-o streams_interface=openxattr",
            "-o inherit",
            "-o uid=\"$BOOT_UID\"",
            "-o gid=\"$BOOT_GID\"",
            "-o allow_other",
            "-o big_writes"
        ]
        if readOnly {
            options.append("-o ro")
        }
        if removeHiberfile {
            options.append("-o remove_hiberfile")
        }
        let optionsLine = options.joined(separator: " ")

        let verify = readOnly
            ? "/bin/ls \"$MP\" >/dev/null 2>&1"
            : "/usr/bin/touch \"$MP/.wijaya_write_test\" && /bin/rm -f \"$MP/.wijaya_write_test\""

        return """
        set -e
        DEV=\(device)
        WHOLE=\(wholeDisk)
        MP=\(target)
        LOG=/var/log/mount-ntfs-3g.log
        BOOT_UID=$(/usr/bin/stat -f %u /dev/console 2>/dev/null || /usr/bin/id -u)
        BOOT_GID=$(/usr/bin/stat -f %g /dev/console 2>/dev/null || /usr/bin/id -g)
        /usr/sbin/diskutil unmountDisk force "$WHOLE" >/dev/null 2>&1 || /sbin/umount -f "$DEV" >/dev/null 2>&1 || true
        /bin/mkdir -p "$MP"
        if ! \(runner) \(optionsLine) "$DEV" "$MP" >> "$LOG" 2>&1; then
            echo \(failMarker)
            /usr/bin/tail -n 40 "$LOG" 2>/dev/null || true
            exit 1
        fi
        \(verify)
        echo \(okMarker)
        """
    }

    static func unmount(volume: Volume) -> String {
        let device = shellQuote(volume.deviceNode)
        let target = shellQuote(volume.candidateMountPoint)
        // FUSE-T mount via NFS tidak dikenali diskutil, jadi unmount lewat path juga.
        return """
        /usr/sbin/diskutil unmount force \(device) 2>&1 \\
          || /usr/sbin/diskutil unmount force \(target) 2>&1 \\
          || /sbin/umount \(target) 2>&1 \\
          || /sbin/umount -f \(target) 2>&1
        """
    }

    static func eject(volume: Volume) -> String {
        let wholeDisk = shellQuote(volume.wholeDisk)
        let target = shellQuote(volume.candidateMountPoint)
        return """
        /usr/sbin/diskutil unmount force \(target) >/dev/null 2>&1 || /sbin/umount -f \(target) >/dev/null 2>&1 || true
        /usr/sbin/diskutil eject \(wholeDisk) 2>&1
        """
    }

    static func repair(volume: Volume, ntfsfixPath: String) -> String {
        let device = shellQuote(volume.deviceNode)
        return """
        /usr/sbin/diskutil unmount force \(device) >/dev/null 2>&1 || true
        \(shellQuote(ntfsfixPath)) -d \(device) 2>&1
        """
    }
}
