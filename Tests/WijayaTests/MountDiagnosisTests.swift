import XCTest
@testable import Wijaya

final class MountDiagnosisTests: XCTestCase {

    func testEpermIsFlaggedAsFullDiskAccess() {
        let text = """
        Error opening '/dev/disk12s1': Operation not permitted
        Failed to mount '/dev/disk12s1': Operation not permitted
        """
        let diagnosis = MountService.diagnose(text: text)
        XCTAssertTrue(diagnosis.needsFullDiskAccess)
        XCTAssertTrue(diagnosis.advice.contains("Full Disk Access"))
    }

    func testHibernationIsDetected() {
        let text = "The NTFS partition is in an unsafe state. Please resume and shutdown Windows fully (no hibernation or fast restarting)"
        let diagnosis = MountService.diagnose(text: text)
        XCTAssertFalse(diagnosis.needsFullDiskAccess)
        XCTAssertTrue(diagnosis.advice.contains("Hapus hiberfil"))
    }

    func testBothProblemsReported() {
        let text = """
        Error opening '/dev/disk12s1': Operation not permitted
        The NTFS partition is hibernated. Please resume Windows and turn it off properly.
        """
        let diagnosis = MountService.diagnose(text: text)
        XCTAssertTrue(diagnosis.needsFullDiskAccess)
        XCTAssertTrue(diagnosis.advice.contains("Full Disk Access"))
        XCTAssertTrue(diagnosis.advice.contains("Hapus hiberfil"))
    }

    func testCleanTextGivesNoAdvice() {
        let diagnosis = MountService.diagnose(text: "mounted fine")
        XCTAssertFalse(diagnosis.needsFullDiskAccess)
        XCTAssertTrue(diagnosis.advice.isEmpty)
    }
}
