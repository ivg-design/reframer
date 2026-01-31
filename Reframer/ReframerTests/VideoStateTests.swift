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

    func testZoomPercentageValue() {
        videoState.zoomScale = 1.234
        XCTAssertEqual(videoState.zoomPercentageValue, 123.4, accuracy: 0.01, "zoomPercentageValue should be 123.4")
    }

    func testOpacityPercentageValue() {
        videoState.opacity = 0.567
        XCTAssertEqual(videoState.opacityPercentageValue, 56.7, accuracy: 0.01, "opacityPercentageValue should be 56.7")
    }

    // MARK: - F-VP-005: Frame State

    func testFrameDefaults() {
        XCTAssertEqual(videoState.currentFrame, 0, "Default current frame should be 0")
        XCTAssertEqual(videoState.totalFrames, 0, "Default total frames should be 0")
        XCTAssertEqual(videoState.frameRate, 30.0, "Default frame rate should be 30.0")
    }

    func testFrameRateCanBeSet() {
        videoState.frameRate = 60.0
        XCTAssertEqual(videoState.frameRate, 60.0, "Frame rate should be settable")
    }

    func testCurrentTimeDefaults() {
        XCTAssertEqual(videoState.currentTime, 0, "Default current time should be 0")
        XCTAssertEqual(videoState.duration, 0, "Default duration should be 0")
    }

    // MARK: - F-VP-005: Time Formatting

    func testFormattedCurrentTimeZero() {
        videoState.currentTime = 0
        XCTAssertEqual(videoState.formattedCurrentTime, "0:00", "0 seconds should format as 0:00")
    }

    func testFormattedCurrentTimeSeconds() {
        videoState.currentTime = 45
        XCTAssertEqual(videoState.formattedCurrentTime, "0:45", "45 seconds should format as 0:45")
    }

    func testFormattedCurrentTimeMinutes() {
        videoState.currentTime = 125
        XCTAssertEqual(videoState.formattedCurrentTime, "2:05", "125 seconds should format as 2:05")
    }

    func testFormattedDuration() {
        videoState.duration = 300
        XCTAssertEqual(videoState.formattedDuration, "5:00", "300 seconds should format as 5:00")
    }

    func testFormattedTimeNegative() {
        videoState.currentTime = -5
        XCTAssertEqual(videoState.formattedCurrentTime, "0:00", "Negative time should format as 0:00")
    }

    func testFormattedTimeInfinite() {
        videoState.currentTime = Double.infinity
        XCTAssertEqual(videoState.formattedCurrentTime, "0:00", "Infinite time should format as 0:00")
    }

    // MARK: - F-ZP-001: Zoom Adjustments

    func testAdjustZoomPositive() {
        videoState.zoomScale = 1.0
        videoState.adjustZoom(byPercent: 10.0)
        XCTAssertEqual(videoState.zoomScale, 1.1, accuracy: 0.001, "Zoom should increase by 10%")
    }

    func testAdjustZoomNegative() {
        videoState.zoomScale = 1.0
        videoState.adjustZoom(byPercent: -5.0)
        XCTAssertEqual(videoState.zoomScale, 0.95, accuracy: 0.001, "Zoom should decrease by 5%")
    }

    func testAdjustZoomFine() {
        videoState.zoomScale = 1.0
        videoState.adjustZoom(byPercent: 0.1)
        XCTAssertEqual(videoState.zoomScale, 1.001, accuracy: 0.0001, "Zoom should increase by 0.1%")
    }

    func testAdjustZoomClampsToMinimum() {
        videoState.zoomScale = 0.15 // 15%
        videoState.adjustZoom(byPercent: -10.0)
        XCTAssertGreaterThanOrEqual(videoState.zoomScale, 0.1, "Zoom should not go below 10%")
    }

    func testAdjustZoomClampsToMaximum() {
        videoState.zoomScale = 9.95 // 995%
        videoState.adjustZoom(byPercent: 10.0)
        XCTAssertLessThanOrEqual(videoState.zoomScale, 10.0, "Zoom should not exceed 1000%")
    }

    // MARK: - F-ZP-005: Zoom Input (setZoomPercentage with Double)

    func testSetZoomPercentageDouble() {
        videoState.setZoomPercentage(123.5)
        XCTAssertEqual(videoState.zoomScale, 1.235, accuracy: 0.001, "setZoomPercentage(123.5) should work")
    }

    func testSetZoomPercentageDoubleClampsMin() {
        videoState.setZoomPercentage(5.0)
        XCTAssertEqual(videoState.zoomScale, 0.1, "Should clamp to 10%")
    }

    func testSetZoomPercentageDoubleClampsMax() {
        videoState.setZoomPercentage(1500.0)
        XCTAssertEqual(videoState.zoomScale, 10.0, "Should clamp to 1000%")
    }

    // MARK: - F-OP-001: Opacity Slider Precision

    func testSetOpacityPercentagePrecision() {
        videoState.setOpacityPercentage(33)
        XCTAssertEqual(videoState.opacity, 0.33, accuracy: 0.001, "Opacity 33% should be 0.33")
    }

    func testSetOpacityPercentageMin() {
        videoState.setOpacityPercentage(1)
        XCTAssertEqual(videoState.opacity, 0.02, "Opacity 1% should clamp to 2%")
    }

    func testSetOpacityPercentageMax() {
        videoState.setOpacityPercentage(100)
        XCTAssertEqual(videoState.opacity, 1.0, "Opacity 100% should be 1.0")
    }

    // MARK: - F-VP-008: Volume Control

    func testToggleMuteToUnmuted() {
        XCTAssertTrue(videoState.isMuted)
        videoState.toggleMute()
        XCTAssertFalse(videoState.isMuted)
        XCTAssertEqual(videoState.volume, 0.5, "Unmute should set volume to 0.5")
    }

    func testToggleMuteBackToMuted() {
        videoState.toggleMute() // unmute
        videoState.toggleMute() // mute again
        XCTAssertTrue(videoState.isMuted)
        XCTAssertEqual(videoState.volume, 0.0, "Mute should set volume to 0.0")
    }

    // MARK: - Video Loading State

    func testVideoLoadedDefaultState() {
        XCTAssertFalse(videoState.isVideoLoaded, "Video should not be loaded by default")
        XCTAssertNil(videoState.videoURL, "Video URL should be nil by default")
    }

    func testVideoNaturalSizeDefault() {
        XCTAssertEqual(videoState.videoNaturalSize, .zero, "Default video size should be .zero")
    }

    // MARK: - F-UI-004: Help Modal State

    func testShowHelpDefault() {
        XCTAssertFalse(videoState.showHelp, "Help should be hidden by default")
    }

    func testShowHelpToggle() {
        videoState.showHelp = true
        XCTAssertTrue(videoState.showHelp)
        videoState.showHelp = false
        XCTAssertFalse(videoState.showHelp)
    }

    // MARK: - Playback State

    func testIsPlayingDefault() {
        XCTAssertFalse(videoState.isPlaying, "Video should not be playing by default")
    }

    func testIsPlayingToggle() {
        videoState.isPlaying = true
        XCTAssertTrue(videoState.isPlaying)
        videoState.isPlaying = false
        XCTAssertFalse(videoState.isPlaying)
    }

    // MARK: - F-ZP-002: Pan Only When Zoomed (State Setup)

    func testPanRequiresZoom() {
        // This test documents the expected behavior: pan should only work when zoomed > 100%
        // The actual enforcement is in VideoPlayerView, but state should support any pan value
        videoState.zoomScale = 1.0
        videoState.panOffset = CGSize(width: 100, height: 100)
        XCTAssertEqual(videoState.panOffset, CGSize(width: 100, height: 100), "State should store pan even at 100% zoom")

        // Reset should work regardless
        videoState.resetView()
        XCTAssertEqual(videoState.panOffset, .zero, "Reset should clear pan")
    }
}
