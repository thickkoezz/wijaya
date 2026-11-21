import Foundation

/// Memasang/menghapus auto-mount latar belakang:
///  - skrip mount  -> /usr/local/libexec/wijaya-automount.sh (root)
///  - aturan sudo  -> /etc/sudoers.d/wijaya-automount (NOPASSWD, root)
///  - LaunchAgent  -> ~/Library/LaunchAgents/com.mieky.wijaya.automount.plist (user)
///
/// LaunchAgent memanggil `sudo -n <skrip>` saat /Volumes berubah, sehingga disk NTFS
/// otomatis di-mount read-write tanpa prompt, di konteks sesi user.
struct AutoMountInstaller {
    static let label = "com.mieky.wijaya.automount"
    static let scriptInstallPath = "/usr/local/libexec/wijaya-automount.sh"
    static let sudoersPath = "/etc/sudoers.d/wijaya-automount"

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
        guard let bundledScript = Bundle.main.path(forResource: "wijaya-automount", ofType: "sh") else {
            return .failure("Skrip auto-mount tidak ditemukan di dalam bundle aplikasi.")
        }

        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plistContents().write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Gagal menulis LaunchAgent.", detail: error.localizedDescription)
        }

        let result = PrivilegedRunner.runAsAdmin(adminInstallScript(bundledScriptPath: bundledScript, user: userName))
        if PrivilegedRunner.isCancelled(result) {
            try? FileManager.default.removeItem(at: plistURL)
            return .failure("Dibatalkan oleh pengguna.")
        }
        guard result.stdout.contains(ScriptBuilder.okMarker) else {
            try? FileManager.default.removeItem(at: plistURL)
            let detail = [result.stdout, result.stderr].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }.joined(separator: "\n")
            return .failure("Gagal memasang komponen sistem (sudoers/skrip).", detail: detail)
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

        let result = PrivilegedRunner.runAsAdmin(adminUninstallScript())
        if PrivilegedRunner.isCancelled(result) {
            return .failure("Auto-mount dihentikan, tapi gagal membersihkan komponen sistem (dibatalkan).")
        }
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
                <string>\(Self.scriptInstallPath)</string>
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

    private func adminInstallScript(bundledScriptPath: String, user: String) -> String {
        let rule = "\(user) ALL=(root) NOPASSWD: \(Self.scriptInstallPath)"
        return """
        set -e
        /bin/mkdir -p /usr/local/libexec
        /usr/bin/install -m 0755 \(ScriptBuilder.shellQuote(bundledScriptPath)) \(Self.scriptInstallPath)
        /usr/sbin/chown root:wheel \(Self.scriptInstallPath)
        /bin/echo \(ScriptBuilder.shellQuote(rule)) > \(Self.sudoersPath)
        /usr/sbin/chown root:wheel \(Self.sudoersPath)
        /bin/chmod 0440 \(Self.sudoersPath)
        /usr/sbin/visudo -cf \(Self.sudoersPath)
        echo \(ScriptBuilder.okMarker)
        """
    }

    private func adminUninstallScript() -> String {
        """
        /bin/rm -f \(Self.sudoersPath) \(Self.scriptInstallPath)
        echo \(ScriptBuilder.okMarker)
        """
    }
}
