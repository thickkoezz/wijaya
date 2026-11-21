import Foundation

/// Menjalankan skrip shell sebagai root lewat prompt administrator bawaan macOS
/// (`osascript` + `do shell script ... with administrator privileges`).
///
/// Satu pemanggilan = satu prompt password. Gabungkan semua langkah root
/// ke dalam satu skrip agar password hanya diminta sekali.
enum PrivilegedRunner {

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
}
