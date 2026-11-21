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
        XCTAssertTrue(diagnosis.advice.contains("tccutil reset"))
    }

    func testEpermUsesDetectedToolPath() {
        let text = "Error opening '/dev/disk12s1': Operation not permitted"
        let diagnosis = MountService.diagnose(text: text, ntfs3gPath: "/usr/local/bin/ntfs-3g")
        XCTAssertTrue(diagnosis.advice.contains("/usr/local/bin/ntfs-3g"))
    }

    func testHibernationIsDetected() {
        let text = "The NTFS partition is in an unsafe state. Please resume and shutdown Windows fully (no hibernation or fast restarting)"
        let diagnosis = MountService.diagnose(text: text)
        XCTAssertFalse(diagnosis.needsFullDiskAccess)
        XCTAssertTrue(diagnosis.advice.contains("Hapus hiberfil"))
    }

    func testEpermSuppressesSpuriousHibernationHint() {
        // ntfs-3g menempelkan baris "unsafe state" sebagai tebakan generik setiap kali
        // gagal mount, termasuk saat /dev/disk ditolak. Kalau device-nya tidak pernah
        // terbuka (EPERM), jangan tampilkan saran hibernasi yang menyesatkan.
        let text = """
        Error opening '/dev/disk12s1': Operation not permitted
        Failed to mount '/dev/disk12s1': Operation not permitted
        The NTFS partition is in an unsafe state. Please resume and shutdown Windows fully.
        """
        let diagnosis = MountService.diagnose(text: text)
        XCTAssertTrue(diagnosis.needsFullDiskAccess)
        XCTAssertTrue(diagnosis.advice.contains("Full Disk Access"))
        XCTAssertFalse(diagnosis.advice.contains("Hapus hiberfil"))
    }

    func testCleanTextGivesNoAdvice() {
        let diagnosis = MountService.diagnose(text: "mounted fine")
        XCTAssertFalse(diagnosis.needsFullDiskAccess)
        XCTAssertTrue(diagnosis.advice.isEmpty)
    }
}
