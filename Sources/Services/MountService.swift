import Foundation

struct ActionOutcome: Sendable {
    let success: Bool
    let message: String
    let detail: String
    let needsFullDiskAccess: Bool
    /// Helper root belum dipasang / belum diizinkan (perlu "Siapkan akses" sekali).
    let needsHelperSetup: Bool

    static func ok(_ message: String, detail: String = "") -> ActionOutcome {
        ActionOutcome(success: true, message: message, detail: detail, needsFullDiskAccess: false, needsHelperSetup: false)
    }

    static func failure(
        _ message: String,
        detail: String = "",
        needsFullDiskAccess: Bool = false,
        needsHelperSetup: Bool = false
    ) -> ActionOutcome {
        ActionOutcome(
            success: false,
            message: message,
            detail: detail,
            needsFullDiskAccess: needsFullDiskAccess,
            needsHelperSetup: needsHelperSetup
        )
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

        var args = [
            "mount",
            readOnly ? "ro" : "rw",
            volume.deviceNode,
            volume.wholeDisk,
            mountPoint,
            volume.volumeName,
            ntfs3gPath
        ]
        if backend == .fuseT, let library = fuseTLibraryPath {
            args += ["--fuse-t", library]
        }
        if removeHiberfile {
            args.append("--remove-hiberfile")
        }

        let result = PrivilegedRunner.runAsRoot(args)
        if !PrivilegedRunner.isInstalled() || PrivilegedRunner.needsInstall(result) {
            return .failure(
                "Akses privileged belum disiapkan.",
                detail: "Jalankan \"Siapkan akses\" sekali (minta password admin), setelah itu mount berjalan tanpa prompt.",
                needsHelperSetup: true
            )
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

        let hints = MountService.diagnose(text: detail, ntfs3gPath: ntfs3gPath)
        let full = [detail, hints.advice].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return .failure("Gagal mount.", detail: full, needsFullDiskAccess: hints.needsFullDiskAccess)
    }

    struct Diagnosis: Sendable {
        let needsFullDiskAccess: Bool
        let advice: String
    }

    /// Mengubah pesan mentah ntfs-3g menjadi saran yang bisa ditindak.
    static func diagnose(text: String, ntfs3gPath: String? = nil) -> Diagnosis {
        let lower = text.lowercased()
        // `Operation not permitted` di sini asalnya dari open() atas /dev/disk yang
        // ditolak macOS (TCC), walau proses berjalan sebagai root.
        let deviceAccessDenied = text.contains("Operation not permitted")
        // ntfs-3g selalu menempelkan saran "unsafe state" setiap kali gagal mount —
        // termasuk ketika gagalnya cuma karena /dev/disk tidak bisa dibuka. Jadi hint
        // hibernasi baru bermakna kalau device-nya memang sempat terbaca.
        let hibernatedHint = (lower.contains("hibernat") || lower.contains("unsafe state")) && !deviceAccessDenied

        var parts: [String] = []
        if deviceAccessDenied {
            let tool = ntfs3gPath ?? "/usr/local/bin/ntfs-3g"
            parts.append("""
            ⚠️ macOS memblokir akses ke /dev/disk (TCC "Full Disk Access"), bahkan sebagai root.
            Buka System Settings → Privacy & Security → Full Disk Access, lalu tambahkan:
              • \(tool)
              • /bin/bash
              • aplikasi Wijaya
            Kalau semuanya sudah terdaftar tapi masih ditolak — khasnya mount pertama berhasil lalu
            mount/unmount berikutnya gagal — reset izin Wijaya lalu jalankan mount lagi:
              tccutil reset SystemPolicyAllFiles dev.mieky.wijaya
            """)
        }
        if hibernatedHint {
            parts.append("""
            ⚠️ NTFS dalam keadaan "hibernated" (Windows Fast Startup / tidak di-shutdown penuh).
            Solusi: boot ke Windows → matikan Fast Startup → Shutdown penuh (bukan Restart/Hibernate).
            Alternatif cepat: tombol "Hapus hiberfil & mount" (membuang sesi Windows yang ter-hibernate).
            """)
        }
        return Diagnosis(needsFullDiskAccess: deviceAccessDenied, advice: parts.joined(separator: "\n\n"))
    }

    func unmount(_ volume: Volume) -> ActionOutcome {
        guard ScriptBuilder.isValidDeviceNode(volume.deviceNode) else {
            return .failure("Device node tidak valid: \(volume.deviceNode)")
        }
        let result = PrivilegedRunner.runAsRoot(["unmount", volume.deviceNode, volume.candidateMountPoint])
        if !PrivilegedRunner.isInstalled() || PrivilegedRunner.needsInstall(result) {
            return helperSetupRequired()
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
        let result = PrivilegedRunner.runAsRoot(["eject", volume.wholeDisk, volume.candidateMountPoint])
        if !PrivilegedRunner.isInstalled() || PrivilegedRunner.needsInstall(result) {
            return helperSetupRequired()
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
        let result = PrivilegedRunner.runAsRoot(["repair", volume.deviceNode, ntfsfixPath])
        if !PrivilegedRunner.isInstalled() || PrivilegedRunner.needsInstall(result) {
            return helperSetupRequired()
        }
        if result.succeeded {
            return .ok("Perbaikan selesai untuk \(volume.displayName).", detail: combine(result))
        }
        return .failure("Perbaikan gagal.", detail: combine(result))
    }

    private func helperSetupRequired() -> ActionOutcome {
        .failure(
            "Akses privileged belum disiapkan.",
            detail: "Jalankan \"Siapkan akses\" sekali (minta password admin), setelah itu operasi berjalan tanpa prompt.",
            needsHelperSetup: true
        )
    }

    private func combine(_ result: ProcessResult) -> String {
        [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
