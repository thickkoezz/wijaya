import Foundation

/// Mode diagnostik headless: `Wijaya --scan` mencetak status FUSE dan daftar
/// volume ke stdout lalu keluar. Berguna untuk verifikasi lewat terminal.
enum DiagnosticsCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--scan") || args.contains("--diagnose") else { return }

        let status = FuseDiagnostics.detect()
        print("=== Wijaya diagnostics ===")
        print("ntfs-3g : \(status.ntfs3gPath ?? "(not found)")  fuseT=\(status.ntfs3gLinkedFuseT)")
        print("ntfsfix : \(status.ntfsfixPath ?? "(not found)")")
        print("macFUSE : \(status.macfuseInstalled ? "installed" : "missing")  kextLoaded=\(status.kextLoaded.map(String.init) ?? "unknown")")
        print("FUSE-T  : \(status.fuseTPath ?? "(not found)")")
        let backends = status.availableBackends.map(\.displayName).joined(separator: ", ")
        print("backends: \(backends.isEmpty ? "(none)" : backends)")
        print("status  : \(status.title)")

        print("")
        print("=== Volumes ===")
        let volumes = DiskScanner().scan()
        if volumes.isEmpty {
            print("(none)")
        }
        for volume in volumes {
            print("- \(volume.displayName) [\(volume.fileSystem.displayName)] \(volume.deviceNode) \(volume.sizeText)")
            print("    state=\(volume.mountState.label)  mount=\(volume.mountPoint ?? "-")  whole=\(volume.wholeDisk)  external=\(volume.isExternal)")
        }
        exit(0)
    }
}
