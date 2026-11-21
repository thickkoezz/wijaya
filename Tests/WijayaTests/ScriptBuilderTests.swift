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

    func testInstallScriptLocksDownSingleHelperPath() {
        let script = PrivilegedRunner.installScript(
            bundledHelperPath: "/Applications/Wijaya.app/Contents/Resources/wijaya-ntfsctl.sh",
            user: "mieky"
        )
        XCTAssertTrue(script.contains("NOPASSWD: /usr/local/libexec/wijaya-ntfsctl"))
        XCTAssertTrue(script.contains("visudo -cf"))
        XCTAssertTrue(script.contains(ScriptBuilder.okMarker))
    }
}
