import Foundation

enum FuseBackend: String, CaseIterable, Identifiable, Sendable {
    case macFUSE
    case fuseT

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macFUSE: return "macFUSE"
        case .fuseT: return "FUSE-T (tanpa reboot)"
        }
    }

    var isExperimental: Bool { self == .fuseT }
}

struct FuseStatus: Sendable {
    enum Kind: Sendable {
        case ready
        case missingNTFS
        case missingMacFUSE
        case kextNotLoaded
        case unknown
    }

    let kind: Kind
    let ntfs3gPath: String?
    let ntfsfixPath: String?
    let macfuseInstalled: Bool
    let kextLoaded: Bool?
    let fuseTPath: String?
    /// true bila binary ntfs-3g sudah tertaut langsung ke libfuse-t (tak butuh macFUSE).
    let ntfs3gLinkedFuseT: Bool

    static let unknown = FuseStatus(
        kind: .unknown,
        ntfs3gPath: nil,
        ntfsfixPath: nil,
        macfuseInstalled: false,
        kextLoaded: nil,
        fuseTPath: nil,
        ntfs3gLinkedFuseT: false
    )

    /// Backend yang bisa dipakai (urut prioritas).
    var availableBackends: [FuseBackend] {
        var backends: [FuseBackend] = []
        if macfuseInstalled { backends.append(.macFUSE) }
        if fuseTPath != nil { backends.append(.fuseT) }
        return backends
    }

    /// Backend yang direkomendasikan: macFUSE bila benar-benar siap, lalu FUSE-T.
    var recommendedBackend: FuseBackend? {
        if kind == .ready { return .macFUSE }
        if fuseTPath != nil { return .fuseT }
        if macfuseInstalled { return .macFUSE }
        return nil
    }

    /// Ada backend yang bisa dicoba?
    var hasUsableBackend: Bool {
        ntfs3gPath != nil && (macfuseInstalled || fuseTPath != nil)
    }

    var ntfs3gAvailable: Bool { ntfs3gPath != nil }

    var title: String {
        switch kind {
        case .ready: return "Siap"
        case .missingNTFS: return "ntfs-3g belum terpasang"
        case .missingMacFUSE: return "macFUSE / FUSE-T belum terpasang"
        case .kextNotLoaded: return "macFUSE belum aktif"
        case .unknown: return "Status FUSE tidak diketahui"
        }
    }

    var detail: [String] {
        switch kind {
        case .ready, .unknown:
            return ["Backend siap. Jalankan mount untuk verifikasi; error akan tampil di log."]
        case .missingNTFS:
            return [
                "Install lewat Homebrew:",
                "  brew tap gromgit/fuse",
                "  brew install ntfs-3g-mac"
            ]
        case .missingMacFUSE:
            return [
                "Pilih salah satu backend:",
                "  brew install --cask macfuse     # fidelity terbaik (perlu izin kext)",
                "  brew install --cask fuse-t      # tanpa reboot, experimental"
            ]
        case .kextNotLoaded:
            return [
                "macFUSE terpasang tapi kernel extension belum aktif (butuh Reduced Security).",
                "Opsi cepat: pakai backend FUSE-T (tanpa reboot).",
                "Opsi penuh: System Settings → Privacy & Security → izinkan macFUSE,",
                "lalu jika perlu set Reduced Security di Recovery Mode dan restart."
            ]
        }
    }
}

enum FuseDiagnostics {
    static let ntfs3gCandidates = [
        "/usr/local/bin/ntfs-3g",
        "/opt/homebrew/bin/ntfs-3g",
        "/opt/homebrew/sbin/mount_ntfs"
    ]
    static let ntfsfixCandidates = [
        "/opt/homebrew/bin/ntfsfix",
        "/usr/local/bin/ntfsfix",
        "/opt/homebrew/sbin/ntfsfix"
    ]
    static let macfusePaths = [
        "/Library/Filesystems/macfuse.fs",
        "/usr/local/lib/libfuse.2.dylib"
    ]
    static let fuseTLibraryCandidates = [
        "/usr/local/lib/libfuse-t.dylib",
        "/usr/local/lib/libfuse-t-1.0.dylib"
    ]

    static func detect() -> FuseStatus {
        let ntfs3g = ProcessRunner.firstExisting(ntfs3gCandidates)
        let ntfsfix = ProcessRunner.firstExisting(ntfsfixCandidates)
        let macfuseInstalled = macfusePaths.contains { FileManager.default.fileExists(atPath: $0) }
        let fuseTPath = ProcessRunner.firstExisting(fuseTLibraryCandidates)
        let kextLoaded = isKextLoaded()

        let kind: FuseStatus.Kind
        if ntfs3g == nil {
            kind = .missingNTFS
        } else if kextLoaded == true {
            kind = .ready
        } else if kextLoaded == false {
            kind = .kextNotLoaded
        } else if macfuseInstalled || fuseTPath != nil {
            kind = .unknown
        } else {
            kind = .missingMacFUSE
        }

        return FuseStatus(
            kind: kind,
            ntfs3gPath: ntfs3g,
            ntfsfixPath: ntfsfix,
            macfuseInstalled: macfuseInstalled,
            kextLoaded: kextLoaded,
            fuseTPath: fuseTPath,
            ntfs3gLinkedFuseT: ntfs3g.map(linksFuseT) ?? false
        )
    }

    /// Cek apakah binary ntfs-3g tertaut langsung ke libfuse-t (bukan libfuse macFUSE).
    static func linksFuseT(_ path: String) -> Bool {
        let result = ProcessRunner.run("/usr/bin/otool", ["-L", path])
        return result.succeeded && result.stdout.contains("libfuse-t")
    }

    private static func isKextLoaded() -> Bool? {
        let bundleID = "io.macfuse.fs"

        // macFUSE 5.x dapat memakai system extension (FSKit), bukan kext.
        let extensions = ProcessRunner.run("/usr/bin/systemextensionsctl", ["list"])
        if extensions.succeeded {
            let output = extensions.stdout.lowercased()
            if output.contains("macfuse") && output.contains("activated enabled") {
                return true
            }
        }

        let result = ProcessRunner.run("/usr/bin/kmutil", ["showloaded", "--bundle-identifier", bundleID])
        if result.succeeded {
            return result.stdout.contains(bundleID)
        }
        if result.stderr.localizedCaseInsensitiveContains("no such") ||
            result.stderr.localizedCaseInsensitiveContains("not found") {
            return false
        }
        return nil
    }
}
