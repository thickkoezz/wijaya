import Foundation
import AppKit

@MainActor
final class VolumeListViewModel: ObservableObject {
    @Published private(set) var volumes: [Volume] = []
    @Published private(set) var fuseStatus: FuseStatus = .unknown
    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var busyVolumeID: String?
    @Published private(set) var isRefreshing = false
    @Published var selectedBackend: FuseBackend?
    @Published private(set) var needsFullDiskAccess = false
    @Published private(set) var helperReady = true
    @Published private(set) var helperBusy = false
    @Published private(set) var autoMountEnabled = false
    @Published private(set) var autoMountBusy = false

    private let scanner = DiskScanner()
    private let autoMount = AutoMountInstaller()

    func bootstrap() {
        fuseStatus = FuseDiagnostics.detect()
        selectedBackend = fuseStatus.recommendedBackend
        autoMountEnabled = autoMount.isEnabled()
        helperReady = PrivilegedRunner.isInstalled()
        append(.info, "Wijaya siap. ntfs-3g: \(fuseStatus.ntfs3gPath ?? "tidak ditemukan")")
        if let backend = selectedBackend {
            append(.info, "Backend FUSE: \(backend.displayName)")
        } else {
            append(.error, "Tidak ada backend FUSE yang siap (macFUSE kext belum aktif / FUSE-T belum terpasang).")
        }
        refresh()
    }

    func selectBackend(_ backend: FuseBackend) {
        selectedBackend = backend
        append(.info, "Backend diganti ke \(backend.displayName).")
    }

    /// Pasang root helper + aturan sudoers sekali (minta password admin). Setelah ini
    /// operasi privileged berjalan lewat `sudo -n` tanpa prompt.
    func installHelper() {
        guard !helperBusy else { return }
        guard let bundled = Bundle.main.path(forResource: "wijaya-ntfsctl", ofType: "sh") else {
            append(.error, "Helper wijaya-ntfsctl tidak ditemukan di dalam bundle aplikasi.")
            return
        }
        let user = NSUserName()
        helperBusy = true
        append(.info, "Menyiapkan akses privileged (sekali, minta password admin)…")
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ActionOutcome in
                let result = PrivilegedRunner.install(bundledHelperPath: bundled, user: user)
                if PrivilegedRunner.isCancelled(result) {
                    return .failure("Dibatalkan oleh pengguna.")
                }
                if result.stdout.contains(ScriptBuilder.okMarker) {
                    return .ok("Akses privileged siap — mount berikutnya tanpa prompt.")
                }
                let detail = [result.stdout, result.stderr]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }.joined(separator: "\n")
                return .failure("Gagal menyiapkan akses privileged.", detail: detail)
            }.value
            self.helperReady = PrivilegedRunner.isInstalled()
            self.helperBusy = false
            self.append(outcome.success ? .success : .error, outcome.message)
            if !outcome.detail.isEmpty {
                self.append(outcome.success ? .info : .error, outcome.detail)
            }
        }
    }

    func toggleAutoMount() {
        guard !autoMountBusy else { return }
        let installer = autoMount
        let enabling = !autoMountEnabled
        autoMountBusy = true
        append(.info, enabling ? "Memasang auto-mount (minta password admin)…" : "Mematikan auto-mount…")
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                enabling ? installer.enable() : installer.disable()
            }.value
            self.autoMountEnabled = installer.isEnabled()
            self.helperReady = PrivilegedRunner.isInstalled()
            self.autoMountBusy = false
            self.append(outcome.success ? .success : .error, outcome.message)
            if !outcome.detail.isEmpty {
                self.append(.error, outcome.detail)
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let scanned = await Task.detached(priority: .userInitiated) { [scanner] in scanner.scan() }.value
            self.volumes = scanned
            self.isRefreshing = false
        }
    }

    func mountReadWrite(_ volume: Volume) {
        perform(volume, action: "mount read-write") { service in service.mountReadWrite(volume) }
    }

    func forceMountReadWrite(_ volume: Volume) {
        perform(volume, action: "mount read-write (hapus hiberfil)") { service in service.mountReadWrite(volume, removeHiberfile: true) }
    }

    func mountReadOnly(_ volume: Volume) {
        perform(volume, action: "mount read-only") { service in service.mountReadOnly(volume) }
    }

    func unmount(_ volume: Volume) {
        perform(volume, action: "unmount") { service in service.unmount(volume) }
    }

    func eject(_ volume: Volume) {
        perform(volume, action: "eject") { service in service.eject(volume) }
    }

    func repair(_ volume: Volume) {
        perform(volume, action: "repair") { service in service.repair(volume) }
    }

    func reveal(_ volume: Volume) {
        guard let mountPoint = volume.mountPoint else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountPoint)
    }

    private func perform(_ volume: Volume, action: String, _ work: @escaping @Sendable (MountService) -> ActionOutcome) {
        guard let service = currentService() else {
            append(.error, "ntfs-3g tidak ditemukan. Install: brew install ntfs-3g-mac")
            return
        }
        guard busyVolumeID == nil else { return }
        busyVolumeID = volume.id
        append(.info, "\(volume.displayName): menjalankan \(action)…")

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { work(service) }.value
            self.busyVolumeID = nil
            if outcome.needsFullDiskAccess {
                self.needsFullDiskAccess = true
            }
            if outcome.needsHelperSetup {
                self.helperReady = PrivilegedRunner.isInstalled()
            }
            self.append(outcome.success ? .success : .error, outcome.message)
            if !outcome.detail.isEmpty {
                self.append(outcome.success ? .info : .error, outcome.detail)
            }
            self.refresh()
        }
    }

    private func currentService() -> MountService? {
        guard let ntfs3g = fuseStatus.ntfs3gPath, let backend = selectedBackend else { return nil }
        // Kalau binary ntfs-3g sudah tertaut FUSE-T, tidak perlu interpose DYLD.
        let needsInterposition = (backend == .fuseT && !fuseStatus.ntfs3gLinkedFuseT)
        return MountService(
            ntfs3gPath: ntfs3g,
            ntfsfixPath: fuseStatus.ntfsfixPath,
            backend: backend,
            fuseTLibraryPath: needsInterposition ? fuseStatus.fuseTPath : nil
        )
    }

    private func append(_ level: LogEntry.Level, _ message: String) {
        logs.append(LogEntry(level: level, message: message))
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }
}
