import Foundation

struct MountEntry: Equatable, Sendable {
    let device: String
    let mountPoint: String
    let fsType: String
    let readOnly: Bool

    /// FUSE-T memount lewat NFS: `/sbin/mount` menampilkan `fuse-t:/<label> on /Volumes/<label> (nfs)`.
    var isFuseT: Bool {
        device.hasPrefix("fuse-t:") || fsType.lowercased() == "nfs"
    }

    var isFuse: Bool {
        let t = fsType.lowercased()
        return t.contains("fuse") || t.contains("macfuse") || t.contains("osxfuse") || isFuseT
    }
}

/// Membaca daftar volume via `diskutil` dan menggabungkannya dengan tabel `mount`
/// untuk mengetahui apakah sebuah volume NTFS sudah di-mount read-write lewat
/// macFUSE/ntfs-3g atau masih read-only dari driver bawaan macOS.
struct DiskScanner {
    static let diskutilPath = "/usr/sbin/diskutil"
    static let mountPath = "/sbin/mount"

    func scan() -> [Volume] {
        let listResult = ProcessRunner.run(DiskScanner.diskutilPath, ["list", "-plist"])
        guard listResult.succeeded,
              let data = listResult.stdout.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else {
            return []
        }

        let identifiers = DiskScanner.collectPartitionIdentifiers(plist)
        let mountTable = DiskScanner.parseMountTable(ProcessRunner.run(DiskScanner.mountPath, []).stdout)

        var volumes: [Volume] = []
        for identifier in identifiers {
            let infoResult = ProcessRunner.run(DiskScanner.diskutilPath, ["info", "-plist", identifier])
            guard infoResult.succeeded,
                  let infoData = infoResult.stdout.data(using: .utf8),
                  let infoPlist = try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil),
                  let dict = infoPlist as? [String: Any]
            else {
                continue
            }
            if let volume = DiskScanner.makeVolume(from: dict, mountTable: mountTable) {
                volumes.append(volume)
            }
        }

        return volumes.sorted { lhs, rhs in
            if lhs.isExternal != rhs.isExternal { return lhs.isExternal }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    // MARK: - Pure helpers (dapat diuji)

    static func collectPartitionIdentifiers(_ plist: Any) -> [String] {
        var identifiers: [String] = []
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                for (key, value) in dict {
                    if key == "DeviceIdentifier", let identifier = value as? String {
                        if identifier.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
                           !identifiers.contains(identifier) {
                            identifiers.append(identifier)
                        }
                    } else {
                        walk(value)
                    }
                }
            } else if let array = node as? [Any] {
                for element in array { walk(element) }
            }
        }
        walk(plist)
        return identifiers
    }

    static func parseMountTable(_ text: String) -> [MountEntry] {
        var entries: [MountEntry] = []
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            guard let onRange = line.range(of: " on ") else { continue }
            let device = String(line[line.startIndex..<onRange.lowerBound])
            let rest = line[onRange.upperBound...]
            guard let openRange = rest.range(of: " (", options: .backwards),
                  rest.hasSuffix(")") else {
                continue
            }
            let mountPoint = String(rest[rest.startIndex..<openRange.lowerBound])
            let optionsText = String(rest[openRange.upperBound..<rest.index(before: rest.endIndex)])
            let options = optionsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let fsType = options.first ?? ""
            let readOnly = options.contains("rdonly") || options.contains("read-only")
            entries.append(MountEntry(device: device, mountPoint: mountPoint, fsType: fsType, readOnly: readOnly))
        }
        return entries
    }

    static func makeVolume(from info: [String: Any], mountTable: [MountEntry]) -> Volume? {
        guard let deviceIdentifier = info["DeviceIdentifier"] as? String,
              let deviceNode = info["DeviceNode"] as? String,
              isValidPartitionNode(deviceNode) else {
            return nil
        }
        if let isWhole = info["WholeDisk"] as? Bool, isWhole { return nil }

        let fsType = (info["FilesystemType"] as? String) ?? ""
        let fsName = info["FilesystemName"] as? String
        let fileSystem = FileSystemKind(fsType: fsType, fsName: fsName)

        let rawVolumeName = (info["VolumeName"] as? String) ?? ""
        let diskutilMount = (info["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let writable = (info["WritableVolume"] as? Bool) ?? (info["Writable"] as? Bool) ?? false
        let readOnly = (info["ReadOnlyVolume"] as? Bool) ?? !writable
        let totalBytes = (info["TotalSize"] as? NSNumber)?.uint64Value ?? 0
        let isInternal = (info["Internal"] as? Bool) ?? true
        let isExternal = !isInternal
        let busProtocol = (info["BusProtocol"] as? String) ?? ""

        let wholeDisk = (info["ParentWholeDisk"] as? String) ?? deviceIdentifier
            .replacingOccurrences(of: #"s[0-9]+$"#, with: "", options: .regularExpression)

        // FUSE-T (NFS) tidak dilaporkan diskutil sebagai ter-mount, jadi cocokkan juga lewat tabel mount.
        let expectedMount = "/Volumes/\(rawVolumeName.isEmpty ? deviceIdentifier : rawVolumeName)"
        let mountEntry = mountTable.first { $0.device == deviceNode }
            ?? mountTable.first { $0.mountPoint == expectedMount }
            ?? mountTable.first { $0.isFuseT && $0.mountPoint == diskutilMount }
        let mountPoint = diskutilMount ?? mountEntry?.mountPoint

        // Sembunyikan volume sistem internal & disk image (mis. simulator).
        if isInternal && !fileSystem.ntfsOrWindows {
            return nil
        }
        if busProtocol == "Disk Image" && !fileSystem.ntfsOrWindows {
            return nil
        }
        if let mp = mountPoint, mp == "/" || mp.hasPrefix("/System/Volumes") {
            return nil
        }

        let state = mountState(fileSystem: fileSystem, readOnly: readOnly, mountEntry: mountEntry, hasMountPoint: mountPoint != nil)

        return Volume(
            id: deviceIdentifier,
            deviceNode: deviceNode,
            volumeName: rawVolumeName,
            fileSystem: fileSystem,
            totalBytes: totalBytes,
            mountPoint: mountPoint,
            isReadOnly: readOnly,
            wholeDisk: wholeDisk,
            isExternal: isExternal,
            mountState: state
        )
    }

    static func mountState(fileSystem: FileSystemKind, readOnly: Bool, mountEntry: MountEntry?, hasMountPoint: Bool) -> MountState {
        guard hasMountPoint else { return .unmounted }
        switch fileSystem {
        case .ntfs:
            if let mountEntry, mountEntry.isFuse {
                return mountEntry.readOnly ? .ntfsReadOnly : .ntfsReadWrite
            }
            return readOnly ? .appleReadOnly : .mountedReadWrite
        case .exfat, .fat32, .apfs, .hfs:
            return readOnly ? .mountedReadOnly : .mountedReadWrite
        case .other:
            return .unsupported
        }
    }

    static func isValidPartitionNode(_ node: String) -> Bool {
        node.range(of: #"^/dev/disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil
    }
}

private extension FileSystemKind {
    var ntfsOrWindows: Bool {
        switch self {
        case .ntfs, .exfat, .fat32: return true
        default: return false
        }
    }
}
