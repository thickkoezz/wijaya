import XCTest
@testable import Wijaya

final class DiskScannerTests: XCTestCase {

    func testParseMountTableFuseEntry() {
        let text = """
        /dev/disk4s1 on /Volumes/My Passport (macfuse, local, nodev, nosuid, synchronous)
        /dev/disk1s1 on / (apfs, sealed, local, read-only, journaled)
        """
        let entries = DiskScanner.parseMountTable(text)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].device, "/dev/disk4s1")
        XCTAssertEqual(entries[0].mountPoint, "/Volumes/My Passport")
        XCTAssertEqual(entries[0].fsType, "macfuse")
        XCTAssertTrue(entries[0].isFuse)
        XCTAssertFalse(entries[0].readOnly)

        XCTAssertTrue(entries[1].readOnly)
        XCTAssertFalse(entries[1].isFuse)
    }

    func testCollectPartitionIdentifiers() {
        let plist: [String: Any] = [
            "AllDisksAndPartitions": [
                [
                    "DeviceIdentifier": "disk4",
                    "Partitions": [
                        ["DeviceIdentifier": "disk4s1"],
                        ["DeviceIdentifier": "disk4s2"]
                    ]
                ],
                ["DeviceIdentifier": "disk5"]
            ]
        ]
        let identifiers = DiskScanner.collectPartitionIdentifiers(plist)
        XCTAssertEqual(identifiers.sorted(), ["disk4s1", "disk4s2"])
        XCTAssertFalse(identifiers.contains("disk4"))
        XCTAssertFalse(identifiers.contains("disk5"))
    }

    func testMakeVolumeNtfsAppleReadOnly() {
        let info = sampleNtfsInfo()
        let volume = DiskScanner.makeVolume(from: info, mountTable: [])
        XCTAssertNotNil(volume)
        XCTAssertEqual(volume?.fileSystem, .ntfs)
        XCTAssertEqual(volume?.mountState, .appleReadOnly)
        XCTAssertTrue(volume?.needsRemountForWrite ?? false)
        XCTAssertEqual(volume?.candidateMountPoint, "/Volumes/My Passport")
    }

    func testMakeVolumeNtfsViaFuseIsWritable() {
        let info = sampleNtfsInfo()
        let table = [MountEntry(device: "/dev/disk4s1", mountPoint: "/Volumes/My Passport", fsType: "macfuse", readOnly: false)]
        let volume = DiskScanner.makeVolume(from: info, mountTable: table)
        XCTAssertEqual(volume?.mountState, .ntfsReadWrite)
        XCTAssertFalse(volume?.needsRemountForWrite ?? true)
    }

    func testMakeVolumeSkipsWholeDisk() {
        var info = sampleNtfsInfo()
        info["WholeDisk"] = true
        XCTAssertNil(DiskScanner.makeVolume(from: info, mountTable: []))
    }

    func testMakeVolumeSkipsDiskImage() {
        let info: [String: Any] = [
            "DeviceIdentifier": "disk5s1",
            "DeviceNode": "/dev/disk5s1",
            "FilesystemType": "apfs",
            "FilesystemName": "APFS",
            "VolumeName": "iOS Simulator",
            "MountPoint": "/Library/Developer/CoreSimulator/Volumes/x",
            "BusProtocol": "Disk Image",
            "TotalSize": NSNumber(value: 9_130_999_808),
            "Internal": false
        ]
        XCTAssertNil(DiskScanner.makeVolume(from: info, mountTable: []))
    }

    func testMakeVolumeWritableNtfsIsNotReadOnly() {
        var info = sampleNtfsInfo()
        info["WritableVolume"] = true
        let volume = DiskScanner.makeVolume(from: info, mountTable: [])
        XCTAssertEqual(volume?.isReadOnly, false)
    }

    func testParseMountTableFuseTEntry() {
        let text = "fuse-t:/My Passport on /Volumes/My Passport (nfs)\n"
        let entries = DiskScanner.parseMountTable(text)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].device, "fuse-t:/My Passport")
        XCTAssertEqual(entries[0].mountPoint, "/Volumes/My Passport")
        XCTAssertEqual(entries[0].fsType, "nfs")
        XCTAssertTrue(entries[0].isFuseT)
        XCTAssertTrue(entries[0].isFuse)
        XCTAssertFalse(entries[0].readOnly)
    }

    func testMakeVolumeDetectsFuseTNfsMountWhenDiskutilBlind() {
        var info = sampleNtfsInfo()
        info["MountPoint"] = "" // diskutil tidak mengenali mount NFS gaya FUSE-T
        let table = [MountEntry(device: "fuse-t:/My Passport", mountPoint: "/Volumes/My Passport", fsType: "nfs", readOnly: false)]
        let volume = DiskScanner.makeVolume(from: info, mountTable: table)
        XCTAssertEqual(volume?.mountState, .ntfsReadWrite)
        XCTAssertEqual(volume?.mountPoint, "/Volumes/My Passport")
    }

    private func sampleNtfsInfo() -> [String: Any] {
        [
            "DeviceIdentifier": "disk4s1",
            "DeviceNode": "/dev/disk4s1",
            "FilesystemType": "ntfs",
            "FilesystemName": "NTFS",
            "VolumeName": "My Passport",
            "MountPoint": "/Volumes/My Passport",
            "WritableVolume": false,
            "TotalSize": NSNumber(value: 4_000_000_000_000),
            "Internal": false,
            "ParentWholeDisk": "disk4",
            "BusProtocol": "USB",
            "WholeDisk": false
        ]
    }
}
