import Foundation

/// Validasi argumen dan helper quoting untuk skrip yang dijalankan sebagai root.
///
/// Logika shell mount/unmount/eject/repair kini tinggal di helper root
/// `Sources/Resources/wijaya-ntfsctl.sh`. Di sisi Swift kita tetap memvalidasi
/// nilai dinamis sebelum dikirim ke helper (defense-in-depth).
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
}
