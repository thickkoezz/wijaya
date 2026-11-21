import Foundation

enum FileSystemKind: String, Sendable {
    case ntfs
    case exfat
    case fat32
    case apfs
    case hfs
    case other

    init(fsType: String, fsName: String?) {
        let type = fsType.lowercased()
        let name = (fsName ?? "").lowercased()
        switch type {
        case "ntfs":
            self = .ntfs
        case "exfat":
            self = .exfat
        case "msdos", "fat", "fat32", "vfat":
            self = .fat32
        case "apfs":
            self = .apfs
        case "hfs":
            self = .hfs
        default:
            if name.contains("ntfs") {
                self = .ntfs
            } else if name.contains("exfat") {
                self = .exfat
            } else if name.contains("fat") {
                self = .fat32
            } else if name.contains("apfs") {
                self = .apfs
            } else if name.contains("hfs") {
                self = .hfs
            } else {
                self = .other
            }
        }
    }

    var displayName: String {
        switch self {
        case .ntfs: return "NTFS"
        case .exfat: return "exFAT"
        case .fat32: return "FAT32"
        case .apfs: return "APFS"
        case .hfs: return "HFS+"
        case .other: return "Unknown"
        }
    }

    var supportsNativeReadWrite: Bool {
        switch self {
        case .exfat, .fat32, .apfs, .hfs: return true
        case .ntfs, .other: return false
        }
    }
}

enum MountState: Sendable {
    case unmounted
    case appleReadOnly
    case ntfsReadWrite
    case ntfsReadOnly
    case mountedReadWrite
    case mountedReadOnly
    case unsupported

    var isMounted: Bool {
        switch self {
        case .unmounted: return false
        default: return true
        }
    }

    var isWritable: Bool {
        switch self {
        case .ntfsReadWrite, .mountedReadWrite: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .unmounted: return "Belum ter-mount"
        case .appleReadOnly: return "Read-Only (macOS)"
        case .ntfsReadWrite: return "Read-Write (ntfs-3g)"
        case .ntfsReadOnly: return "Read-Only (ntfs-3g)"
        case .mountedReadWrite: return "Read-Write (native)"
        case .mountedReadOnly: return "Read-Only (native)"
        case .unsupported: return "Tidak didukung"
        }
    }
}

struct Volume: Identifiable, Hashable, Sendable {
    let id: String
    let deviceNode: String
    let volumeName: String
    let fileSystem: FileSystemKind
    let totalBytes: UInt64
    let mountPoint: String?
    let isReadOnly: Bool
    let wholeDisk: String
    let isExternal: Bool
    let mountState: MountState

    var isNTFS: Bool { fileSystem == .ntfs }

    var displayName: String {
        volumeName.isEmpty ? "Untitled (\(id))" : volumeName
    }

    var candidateMountPoint: String {
        if let mountPoint, !mountPoint.isEmpty {
            return mountPoint
        }
        let safeName = volumeName.isEmpty ? id : volumeName
        return "/Volumes/\(safeName)"
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    var needsRemountForWrite: Bool {
        fileSystem == .ntfs && !mountState.isWritable
    }
}
