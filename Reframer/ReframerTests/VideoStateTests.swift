import XCTest
@testable import Reframer

@MainActor
final class VideoStateTests: XCTestCase {

    var videoState: VideoState!

    override func setUp() {
        super.setUp()
        videoState = VideoState()
    }

    override func tearDown() {
        videoState = nil
        super.tearDown()
    }

    // MARK: - F-OP-002: Opacity Minimum (via setOpacityPercentage)

    func testOpacityClampedToMinimumViaMethod() {
        // setOpacityPercentage should clamp to 2% minimum
        videoState.setOpacityPercentage(0)
        XCTAssertGreaterThanOrEqual(videoState.opacity, 0.02, "Opacity should be clamped to minimum 2%")
    }

    func testOpacityClampedToMaximumViaMethod() {
        // setOpacityPercentage should clamp to 100% maximum
        videoState.setOpacityPercentage(150)
        XCTAssertLessThanOrEqual(videoState.opacity, 1.0, "Opacity should be clamped to maximum 100%")
    }

    func testOpacityValidRangeViaMethod() {
        // Valid opacity values should be preserved
        videoState.setOpacityPercentage(50)
        XCTAssertEqual(videoState.opacity, 0.5, accuracy: 0.001, "Valid opacity should be preserved")
    }

    // MARK: - F-ZP-006: Reset View

    func testResetViewResetsZoom() {
        videoState.zoomScale = 2.0
        videoState.resetView()
        XCTAssertEqual(videoState.zoomScale, 1.0, "Zoom should reset to 100%")
    }

    func testResetViewResetsPan() {
        videoState.panOffset = CGSize(width: 100, height: 100)
        videoState.resetView()
        XCTAssertEqual(videoState.panOffset, .zero, "Pan should reset to origin")
    }

    func testResetViewResetsBothZoomAndPan() {
        videoState.zoomScale = 3.0
        videoState.panOffset = CGSize(width: 200, height: -50)
        videoState.resetView()
        XCTAssertEqual(videoState.zoomScale, 1.0, "Zoom should reset to 100%")
        XCTAssertEqual(videoState.panOffset, .zero, "Pan should reset to origin")
    }

    // MARK: - F-LK-001: Lock State

    func testLockDefaultState() {
        // Lock should be off by default
        XCTAssertFalse(videoState.isLocked, "Lock should be off by default")
    }

    func testLockToggle() {
        XCTAssertFalse(videoState.isLocked)
        videoState.isLocked.toggle()
        XCTAssertTrue(videoState.isLocked, "Lock should toggle to on")
        videoState.isLocked.toggle()
        XCTAssertFalse(videoState.isLocked, "Lock should toggle back to off")
    }

    // MARK: - F-CW-002: Always-on-Top (isAlwaysOnTop)

    func testIsAlwaysOnTopDefaultState() {
        // Window should be always on top by default
        XCTAssertTrue(videoState.isAlwaysOnTop, "Window should be always on top by default")
    }

    func testIsAlwaysOnTopToggle() {
        XCTAssertTrue(videoState.isAlwaysOnTop)
        videoState.isAlwaysOnTop.toggle()
        XCTAssertFalse(videoState.isAlwaysOnTop, "isAlwaysOnTop should toggle to off")
    }

    // MARK: - Zoom Scale Validation

    func testZoomScaleDefaultValue() {
        XCTAssertEqual(videoState.zoomScale, 1.0, "Default zoom should be 100%")
    }

    func testZoomScaleCanBeSet() {
        videoState.zoomScale = 2.0
        XCTAssertEqual(videoState.zoomScale, 2.0, "Zoom should be settable to 200%")
    }

    func testSetZoomPercentage() {
        videoState.setZoomPercentage(200)
        XCTAssertEqual(videoState.zoomScale, 2.0, "setZoomPercentage(200) should set zoomScale to 2.0")
    }

    func testSetZoomPercentageClampsToMinimum() {
        videoState.setZoomPercentage(5)
        XCTAssertGreaterThanOrEqual(videoState.zoomScale, 0.1, "Zoom should be clamped to minimum 10%")
    }

    func testSetZoomPercentageClampsToMaximum() {
        videoState.setZoomPercentage(1500)
        XCTAssertLessThanOrEqual(videoState.zoomScale, 10.0, "Zoom should be clamped to maximum 1000%")
    }

    func testAdjustZoom() {
        videoState.zoomScale = 1.0 // 100%
        videoState.adjustZoom(byPercent: 5.0)
        XCTAssertEqual(videoState.zoomScale, 1.05, accuracy: 0.001, "adjustZoom should increase by 5%")
    }

    // MARK: - Pan Offset Validation

    func testPanOffsetDefaultValue() {
        XCTAssertEqual(videoState.panOffset, .zero, "Default pan should be at origin")
    }

    func testPanOffsetCanBeSet() {
        let newOffset = CGSize(width: 50, height: -25)
        videoState.panOffset = newOffset
        XCTAssertEqual(videoState.panOffset, newOffset, "Pan offset should be settable")
    }

    // MARK: - Volume / Mute

    func testMutedByDefault() {
        XCTAssertTrue(videoState.isMuted, "Should be muted by default")
        XCTAssertEqual(videoState.volume, 0.0, "Volume should be 0 when muted")
    }

    func testToggleMute() {
        videoState.toggleMute()
        XCTAssertFalse(videoState.isMuted, "Should be unmuted after toggle")
        XCTAssertGreaterThan(videoState.volume, 0.0, "Volume should be > 0 when unmuted")
    }

    // MARK: - Computed Properties

    func testZoomPercentage() {
        videoState.zoomScale = 1.5
        XCTAssertEqual(videoState.zoomPercentage, 150, "zoomPercentage should be 150 for 1.5 scale")
    }

    func testOpacityPercentage() {
        videoState.opacity = 0.75
        XCTAssertEqual(videoState.opacityPercentage, 75, "opacityPercentage should be 75 for 0.75 opacity")
    }
}
