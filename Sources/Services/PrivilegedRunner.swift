import Foundation

/// Menjalankan operasi privileged.
///
/// Dua jalur:
///  - `runAsRoot`  : operasi normal (mount/unmount/eject/repair) lewat helper root
///                   yang dipanggil dengan `sudo -n` (aturan sudoers NOPASSWD).
///                   Proses root ini anak langsung Wijaya.app, sehingga atribusi TCC
///                   ("responsible process") menempel ke aplikasi — inilah yang membuat
///                   mount/remount andal (bukan `osascript … with administrator privileges`).
///  - `runAsAdmin` : HANYA untuk memasang helper sekali (butuh root sekaligus). Langkah ini
///                   tidak menyentuh /dev/disk, jadi TCC tidak relevan.
enum PrivilegedRunner {

    static let helperInstallPath = "/usr/local/libexec/wijaya-ntfsctl"
    static let sudoersPath = "/etc/sudoers.d/wijaya-ntfsctl"

    /// Helper root sudah terpasang?
    static func isInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: helperInstallPath)
    }

    /// Jalankan helper sebagai root tanpa prompt (aturan sudoers NOPASSWD).
    static func runAsRoot(_ arguments: [String]) -> ProcessResult {
        ProcessRunner.run("/usr/bin/sudo", ["-n", helperInstallPath] + arguments)
    }

    /// Hasil `sudo -n` menandakan helper belum dipasang / belum diizinkan.
    static func needsInstall(_ result: ProcessResult) -> Bool {
        let err = result.stderr.lowercased()
        return err.contains("a password is required")
            || err.contains("terminal is required")
            || err.contains("is not allowed")
            || err.contains("command not found")
            || err.contains("no such file or directory")
    }

    /// Pasang helper + aturan sudoers (sekali, minta password admin).
    static func install(bundledHelperPath: String, user: String) -> ProcessResult {
        runAsAdmin(installScript(bundledHelperPath: bundledHelperPath, user: user))
    }

    /// Jalankan skrip sebagai root lewat prompt administrator bawaan macOS.
    /// Dipakai hanya untuk pemasangan helper — bukan untuk operasi disk harian.
    static func runAsAdmin(_ script: String) -> ProcessResult {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        return ProcessRunner.run("/usr/bin/osascript", ["-e", appleScript])
    }

    static func isCancelled(_ result: ProcessResult) -> Bool {
        let stderr = result.stderr.lowercased()
        return stderr.contains("-128") || stderr.contains("user canceled") || stderr.contains("user cancelled")
    }

    /// Skrip instalasi helper: salin helper dari bundle ke /usr/local/libexec,
    /// dan izinkan HANYA path itu untuk dijalankan tanpa password oleh user ini.
    static func installScript(bundledHelperPath: String, user: String) -> String {
        let rule = "\(user) ALL=(root) NOPASSWD: \(helperInstallPath)"
        return """
        set -e
        /bin/mkdir -p /usr/local/libexec
        /usr/bin/install -m 0755 \(ScriptBuilder.shellQuote(bundledHelperPath)) \(helperInstallPath)
        /usr/sbin/chown root:wheel \(helperInstallPath)
        /bin/echo \(ScriptBuilder.shellQuote(rule)) > \(sudoersPath)
        /usr/sbin/chown root:wheel \(sudoersPath)
        /bin/chmod 0440 \(sudoersPath)
        /usr/sbin/visudo -cf \(sudoersPath)
        /bin/rm -f /etc/sudoers.d/wijaya-automount /usr/local/libexec/wijaya-automount.sh 2>/dev/null || true
        echo \(ScriptBuilder.okMarker)
        """
    }
}
