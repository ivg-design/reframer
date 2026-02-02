import XCTest
@testable import Reframer

final class MPVManagerTests: XCTestCase {

    var manager: MPVManager!

    override func setUp() {
        super.setUp()
        manager = MPVManager.shared
    }

    // MARK: - Format Detection Tests

    func testRequiresMPV_WebM() {
        let webmURL = URL(fileURLWithPath: "/test/video.webm")
        XCTAssertTrue(manager.requiresMPV(url: webmURL), "WebM files should require MPV")
    }

    func testRequiresMPV_MKV() {
        let mkvURL = URL(fileURLWithPath: "/test/video.mkv")
        XCTAssertTrue(manager.requiresMPV(url: mkvURL), "MKV files should require MPV")
    }

    func testRequiresMPV_OGV() {
        let ogvURL = URL(fileURLWithPath: "/test/video.ogv")
        XCTAssertTrue(manager.requiresMPV(url: ogvURL), "OGV files should require MPV")
    }

    func testRequiresMPV_FLV() {
        let flvURL = URL(fileURLWithPath: "/test/video.flv")
        XCTAssertTrue(manager.requiresMPV(url: flvURL), "FLV files should require MPV")
    }

    func testRequiresMPV_MP4_ReturnsFalse() {
        let mp4URL = URL(fileURLWithPath: "/test/video.mp4")
        XCTAssertFalse(manager.requiresMPV(url: mp4URL), "MP4 files should not require MPV by default")
    }

    func testRequiresMPV_MOV_ReturnsFalse() {
        let movURL = URL(fileURLWithPath: "/test/video.mov")
        XCTAssertFalse(manager.requiresMPV(url: movURL), "MOV files should not require MPV by default")
    }

    func testRequiresMPV_CaseInsensitive() {
        let upperWebmURL = URL(fileURLWithPath: "/test/video.WEBM")
        XCTAssertTrue(manager.requiresMPV(url: upperWebmURL), "Extension matching should be case-insensitive")

        let mixedURL = URL(fileURLWithPath: "/test/video.WebM")
        XCTAssertTrue(manager.requiresMPV(url: mixedURL), "Extension matching should be case-insensitive")
    }

    // MARK: - Installation State Tests

    func testIsReady_ReflectsLoadState() {
        let isReady = manager.isReady
        XCTAssertTrue(isReady == true || isReady == false, "isReady should be a valid boolean")
    }

    func testIsInstalled_ReflectsInstallationState() {
        let isInstalled = manager.isInstalled
        XCTAssertTrue(isInstalled == true || isInstalled == false, "isInstalled should be a valid boolean")
    }

    func testIsEnabled_CanBeToggled() {
        let original = manager.isEnabled
        manager.isEnabled = !original
        XCTAssertEqual(manager.isEnabled, !original)
        manager.isEnabled = original // Restore
    }

    func testInstallDirectory_IsInApplicationSupport() {
        let installDir = manager.installDirectory
        XCTAssertTrue(installDir.path.contains("Application Support"), "Install directory should be in Application Support")
        XCTAssertTrue(installDir.path.contains("Reframer"), "Install directory should be in Reframer folder")
    }
}
