import XCTest
@testable import Wijaya

final class ScriptBuilderTests: XCTestCase {

    func testShellQuoteWrapsInSingleQuotes() {
        XCTAssertEqual(ScriptBuilder.shellQuote("My Passport"), "'My Passport'")
    }

    func testShellQuoteEscapesEmbeddedSingleQuote() {
        XCTAssertEqual(ScriptBuilder.shellQuote("a'b"), "'a'\\''b'")
    }

    func testShellQuoteNeutralisesInjection() {
        let malicious = "x'; rm -rf / #"
        let quoted = ScriptBuilder.shellQuote(malicious)
        XCTAssertEqual(quoted, "'x'\\''; rm -rf / #'")
        XCTAssertFalse(quoted.hasPrefix("x'"))
    }

    func testDeviceNodeValidation() {
        XCTAssertTrue(ScriptBuilder.isValidDeviceNode("/dev/disk4s1"))
        XCTAssertTrue(ScriptBuilder.isValidDeviceNode("/dev/disk12s3"))
        XCTAssertFalse(ScriptBuilder.isValidDeviceNode("/dev/disk4"))
        XCTAssertFalse(ScriptBuilder.isValidDeviceNode("/dev/disk4s1; rm -rf /"))
        XCTAssertFalse(ScriptBuilder.isValidDeviceNode("disk4s1"))
    }

    func testWholeDiskValidation() {
        XCTAssertTrue(ScriptBuilder.isValidWholeDisk("disk4"))
        XCTAssertFalse(ScriptBuilder.isValidWholeDisk("disk4s1"))
        XCTAssertFalse(ScriptBuilder.isValidWholeDisk("/dev/disk4"))
    }

    func testMountScriptContainsMarkerAndQuotedName() {
        let volume = Volume(
            id: "disk4s1",
            deviceNode: "/dev/disk4s1",
            volumeName: "My Passport",
            fileSystem: .ntfs,
            totalBytes: 4_000_000_000_000,
            mountPoint: "/Volumes/My Passport",
            isReadOnly: true,
            wholeDisk: "disk4",
            isExternal: true,
            mountState: .appleReadOnly
        )

        let script = ScriptBuilder.mountReadWrite(
            volume: volume,
            ntfs3gPath: "/opt/homebrew/bin/ntfs-3g",
            mountPoint: "/Volumes/My Passport"
        )

        XCTAssertTrue(script.contains("'/dev/disk4s1'"))
        XCTAssertTrue(script.contains("-o volname='My Passport'"))
        XCTAssertTrue(script.contains("'/opt/homebrew/bin/ntfs-3g'"))
        XCTAssertTrue(script.contains(ScriptBuilder.okMarker))
        XCTAssertTrue(script.contains("diskutil unmountDisk force"))
        XCTAssertFalse(script.contains("DYLD_INSERT_LIBRARIES"))
        XCTAssertFalse(script.contains("remove_hiberfile"))
    }

    func testMountScriptWithRemoveHiberfile() {
        let script = ScriptBuilder.mountReadWrite(
            volume: sampleVolume(),
            ntfs3gPath: "/opt/homebrew/bin/ntfs-3g",
            mountPoint: "/Volumes/My Passport",
            removeHiberfile: true
        )
        XCTAssertTrue(script.contains("-o remove_hiberfile"))
    }

    func testMountReadOnlyScriptUsesRoAndSkipsWriteTest() {
        let script = ScriptBuilder.mountReadOnly(
            volume: sampleVolume(),
            ntfs3gPath: "/usr/local/bin/ntfs-3g",
            mountPoint: "/Volumes/My Passport"
        )
        XCTAssertTrue(script.contains("-o ro"))
        XCTAssertFalse(script.contains("wijaya_write_test"))
    }

    func testMountScriptUsesFuseTInterpositionWhenSelected() {
        let volume = sampleVolume()
        let script = ScriptBuilder.mountReadWrite(
            volume: volume,
            ntfs3gPath: "/opt/homebrew/bin/ntfs-3g",
            mountPoint: "/Volumes/My Passport",
            backend: .fuseT,
            fuseTLibraryPath: "/usr/local/lib/libfuse-t.dylib"
        )
        XCTAssertTrue(script.contains("DYLD_INSERT_LIBRARIES='/usr/local/lib/libfuse-t.dylib'"))
        XCTAssertTrue(script.contains("DYLD_FORCE_FLAT_NAMESPACE=1"))
        XCTAssertTrue(script.contains(ScriptBuilder.okMarker))
    }

    private func sampleVolume() -> Volume {
        Volume(
            id: "disk4s1",
            deviceNode: "/dev/disk4s1",
            volumeName: "My Passport",
            fileSystem: .ntfs,
            totalBytes: 4_000_000_000_000,
            mountPoint: "/Volumes/My Passport",
            isReadOnly: true,
            wholeDisk: "disk4",
            isExternal: true,
            mountState: .appleReadOnly
        )
    }
}
