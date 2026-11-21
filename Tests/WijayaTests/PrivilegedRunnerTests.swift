import XCTest
@testable import Wijaya

final class PrivilegedRunnerTests: XCTestCase {

    private func result(status: Int32, stdout: String = "", stderr: String = "") -> ProcessResult {
        ProcessResult(status: status, stdout: stdout, stderr: stderr)
    }

    func testDetectsPasswordPromptAsNeedsInstall() {
        let r = result(status: 1, stderr: "sudo: a password is required")
        XCTAssertTrue(PrivilegedRunner.needsInstall(r))
    }

    func testDetectsNotAllowedAsNeedsInstall() {
        let r = result(status: 1, stderr: "sudo: /usr/local/libexec/wijaya-ntfsctl is not allowed")
        XCTAssertTrue(PrivilegedRunner.needsInstall(r))
    }

    func testDetectsMissingHelperAsNeedsInstall() {
        let r = result(status: 127, stderr: "sudo: /usr/local/libexec/wijaya-ntfsctl: command not found")
        XCTAssertTrue(PrivilegedRunner.needsInstall(r))
    }

    func testRealMountFailureIsNotNeedsInstall() {
        let r = result(status: 1, stdout: "WIJAYA_FAIL\nError opening '/dev/disk12s1': Operation not permitted")
        XCTAssertFalse(PrivilegedRunner.needsInstall(r))
    }
}
