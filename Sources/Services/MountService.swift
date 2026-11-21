import Foundation

struct ActionOutcome: Sendable {
    let success: Bool
    let message: String
    let detail: String
    let needsFullDiskAccess: Bool

    static func ok(_ message: String, detail: String = "") -> ActionOutcome {
        ActionOutcome(success: true, message: message, detail: detail, needsFullDiskAccess: false)
    }

    static func failure(_ message: String, detail: String = "", needsFullDiskAccess: Bool = false) -> ActionOutcome {
        ActionOutcome(success: false, message: message, detail: detail, needsFullDiskAccess: needsFullDiskAccess)
    }
}

struct MountService: Sendable {
    let ntfs3gPath: String
    let ntfsfixPath: String?
    let backend: FuseBackend
    let fuseTLibraryPath: String?
    let mountLogPath = "/var/log/mount-ntfs-3g.log"

    func mountReadWrite(_ volume: Volume, removeHiberfile: Bool = false) -> ActionOutcome {
        mount(volume, readOnly: false, removeHiberfile: removeHiberfile)
    }

    func mountReadOnly(_ volume: Volume) -> ActionOutcome {
        mount(volume, readOnly: true, removeHiberfile: false)
    }

    private func mount(_ volume: Volume, readOnly: Bool, removeHiberfile: Bool) -> ActionOutcome {
        guard ScriptBuilder.isValidDeviceNode(volume.deviceNode) else {
            return .failure("Device node tidak valid: \(volume.deviceNode)")
        }
        let mountPoint = volume.candidateMountPoint
        let script: String
        if readOnly {
            script = ScriptBuilder.mountReadOnly(
                volume: volume,
                ntfs3gPath: ntfs3gPath,
                mountPoint: mountPoint,
                backend: backend,
                fuseTLibraryPath: fuseTLibraryPath
            )
        } else {
            script = ScriptBuilder.mountReadWrite(
                volume: volume,
                ntfs3gPath: ntfs3gPath,
                mountPoint: mountPoint,
                backend: backend,
                fuseTLibraryPath: fuseTLibraryPath,
                removeHiberfile: removeHiberfile
            )
        }
        let result = PrivilegedRunner.runAsAdmin(script)

        if PrivilegedRunner.isCancelled(result) {
            return .failure("Dibatalkan oleh pengguna.")
        }
        if result.stdout.contains(ScriptBuilder.okMarker) {
            let mode = readOnly ? "read-only" : "read-write"
            return .ok(
                "\(volume.displayName) berhasil di-mount \(mode) di \(mountPoint)",
                detail: result.stdout.replacingOccurrences(of: ScriptBuilder.okMarker + "\n", with: "")
            )
        }

        var detail = result.stdout
        if result.stdout.contains(ScriptBuilder.failMarker) {
            detail = result.stdout.replacingOccurrences(of: ScriptBuilder.failMarker, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if detail.isEmpty {
            detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if detail.isEmpty {
            detail = ProcessRunner.tail(ofFileAt: mountLogPath, lines: 20)
        }

        let hints = MountService.diagnose(text: detail)
        let full = [detail, hints.advice].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return .failure("Gagal mount.", detail: full, needsFullDiskAccess: hints.needsFullDiskAccess)
    }

    struct Diagnosis: Sendable {
        let needsFullDiskAccess: Bool
        let advice: String
    }

    /// Mengubah pesan mentah ntfs-3g menjadi saran yang bisa ditindak.
    static func diagnose(text: String) -> Diagnosis {
        let lower = text.lowercased()
        let eperm = text.contains("Operation not permitted")
        let hibernated = lower.contains("hibernat") || lower.contains("unsafe state")

        var parts: [String] = []
        if eperm {
            parts.append("""
            ⚠️ macOS memblokir akses ke /dev/disk (TCC "Full Disk Access"), bahkan sebagai root.
            Buka System Settings → Privacy & Security → Full Disk Access, lalu tambahkan:
              • /opt/homebrew/bin/ntfs-3g
              • /bin/bash
            (dan aplikasi Wijaya). Setelah itu jalankan mount lagi.
            """)
        }
        if hibernated {
            parts.append("""
            ⚠️ NTFS dalam keadaan "hibernated" (Windows Fast Startup / tidak di-shutdown penuh).
            Solusi: boot ke Windows → matikan Fast Startup → Shutdown penuh (bukan Restart/Hibernate).
            Alternatif cepat: tombol "Hapus hiberfil & mount" (membuang sesi Windows yang ter-hibernate).
            """)
        }
        return Diagnosis(needsFullDiskAccess: eperm, advice: parts.joined(separator: "\n\n"))
    }

    func unmount(_ volume: Volume) -> ActionOutcome {
        guard ScriptBuilder.isValidDeviceNode(volume.deviceNode) else {
            return .failure("Device node tidak valid: \(volume.deviceNode)")
        }
        let result = PrivilegedRunner.runAsAdmin(ScriptBuilder.unmount(volume: volume))
        if PrivilegedRunner.isCancelled(result) {
            return .failure("Dibatalkan oleh pengguna.")
        }
        if result.succeeded {
            return .ok("\(volume.displayName) berhasil di-unmount.", detail: result.stdout)
        }
        return .failure("Gagal unmount.", detail: combine(result))
    }

    func eject(_ volume: Volume) -> ActionOutcome {
        guard ScriptBuilder.isValidWholeDisk(volume.wholeDisk) else {
            return .failure("Nama disk tidak valid: \(volume.wholeDisk)")
        }
        let result = PrivilegedRunner.runAsAdmin(ScriptBuilder.eject(volume: volume))
        if PrivilegedRunner.isCancelled(result) {
            return .failure("Dibatalkan oleh pengguna.")
        }
        if result.succeeded {
            return .ok("\(volume.displayName) berhasil di-eject. Aman untuk dicabut.", detail: result.stdout)
        }
        return .failure("Gagal eject.", detail: combine(result))
    }

    func repair(_ volume: Volume) -> ActionOutcome {
        guard let ntfsfixPath else {
            return .failure("ntfsfix tidak ditemukan.")
        }
        guard ScriptBuilder.isValidDeviceNode(volume.deviceNode) else {
            return .failure("Device node tidak valid: \(volume.deviceNode)")
        }
        let result = PrivilegedRunner.runAsAdmin(ScriptBuilder.repair(volume: volume, ntfsfixPath: ntfsfixPath))
        if PrivilegedRunner.isCancelled(result) {
            return .failure("Dibatalkan oleh pengguna.")
        }
        if result.succeeded {
            return .ok("Perbaikan selesai untuk \(volume.displayName).", detail: combine(result))
        }
        return .failure("Perbaikan gagal.", detail: combine(result))
    }

    private func combine(_ result: ProcessResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
