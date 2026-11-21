import Foundation

/// Memasang/menghapus auto-mount latar belakang.
///
/// Auto-mount memakai root helper yang sama dengan operasi manual
/// (`/usr/local/libexec/wijaya-ntfsctl automount`), dipanggil lewat `sudo -n`.
/// Saat mengaktifkan, helper + aturan sudoers dipasang sekali (minta password admin).
struct AutoMountInstaller {
    static let label = "com.mieky.wijaya.automount"

    private var uid: uid_t { getuid() }
    private var userName: String { NSUserName() }

    var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enable() -> ActionOutcome {
        guard let bundledHelper = Bundle.main.path(forResource: "wijaya-ntfsctl", ofType: "sh") else {
            return .failure("Helper wijaya-ntfsctl tidak ditemukan di dalam bundle aplikasi.")
        }

        // Pasang helper + sudoers sekali (minta password admin).
        let install = PrivilegedRunner.install(bundledHelperPath: bundledHelper, user: userName)
        if PrivilegedRunner.isCancelled(install) {
            return .failure("Dibatalkan oleh pengguna.")
        }
        guard install.stdout.contains(ScriptBuilder.okMarker) else {
            let detail = [install.stdout, install.stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "\n")
            return .failure("Gagal memasang helper sistem.", detail: detail)
        }

        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plistContents().write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Gagal menulis LaunchAgent.", detail: error.localizedDescription)
        }

        _ = ProcessRunner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Self.label)"])
        let bootstrap = ProcessRunner.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])
        if !bootstrap.succeeded {
            _ = ProcessRunner.run("/bin/launchctl", ["load", "-w", plistURL.path])
        }

        return .ok("Auto-mount aktif — disk NTFS akan otomatis read-write saat dicolok.")
    }

    func disable() -> ActionOutcome {
        _ = ProcessRunner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Self.label)"])
        _ = ProcessRunner.run("/bin/launchctl", ["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        return .ok("Auto-mount dimatikan.")
    }

    // MARK: - Isi file

    private func plistContents() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(Self.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/sudo</string>
                <string>-n</string>
                <string>\(PrivilegedRunner.helperInstallPath)</string>
                <string>automount</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>WatchPaths</key>
            <array>
                <string>/Volumes</string>
            </array>
            <key>StandardOutPath</key>
            <string>/tmp/wijaya-automount.out</string>
            <key>StandardErrorPath</key>
            <string>/tmp/wijaya-automount.err</string>
        </dict>
        </plist>
        """
    }
}
