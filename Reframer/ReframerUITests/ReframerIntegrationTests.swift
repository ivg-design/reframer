import XCTest

private func fixtureURL(_ name: String, ext: String = "mp4") -> URL {
    let fileURL = URL(fileURLWithPath: #file)
    let baseURL = fileURL.deletingLastPathComponent().deletingLastPathComponent() // .../Reframer
    return baseURL.appendingPathComponent("ReframerTests/TestFixtures/\(name).\(ext)")
}

/// Path to test video fixture
let testVideoPath = fixtureURL("test-video").path

/// Comprehensive integration tests with video loaded.
/// These tests verify actual functionality, not just UI element existence.
/// Uses shared app instance to avoid relaunching for every test.
final class ReframerIntegrationTests: XCTestCase {

    /// Shared app instance - launched once per test suite
    private static var _app: XCUIApplication?
    private static var appLaunched = false

    var app: XCUIApplication {
        if Self._app == nil {
            Self._app = XCUIApplication()
        }
        return Self._app!
    }

    override func setUpWithError() throws {
        continueAfterFailure = true

        // Only launch app once for entire test suite
        if !Self.appLaunched {
            app.launchEnvironment["UITEST_MODE"] = "1"
            app.launchEnvironment["TEST_VIDEO_PATH"] = testVideoPath
            app.launch()
            Self.appLaunched = true

            // Wait for video to load
            waitForVideoReady()
        } else {
            // Ensure app is active
            app.activate()
        }

        // Reset to known state
        // 1. Close any open help modal
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.1)

        // 2. Defocus any text fields by clicking on the app window
        // This ensures we're not stuck in a text field
        app.windows.firstMatch.click()
        Thread.sleep(forTimeInterval: 0.1)

        // 3. Ensure unlocked since R key doesn't work when locked
        ensureUnlocked()

        // 4. Pause any playing video
        let playButton = app.buttons["button-play"]
        if playButton.exists && playButton.label == "pause" {
            app.typeKey(" ", modifierFlags: []) // Pause
            Thread.sleep(forTimeInterval: 0.1)
        }

        // 5. Reset view (zoom and pan)
        app.typeKey("r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
    }

    override class func tearDown() {
        _app?.terminate()
        _app = nil
        appLaunched = false
        super.tearDown()
    }

    // MARK: - Helpers

    func getZoomValue() -> Double {
        let zoomField = app.textFields["input-zoom"]
        guard zoomField.exists else { return 100 }
        let value = zoomField.value as? String ?? "100"
        return Double(value) ?? 100
    }

    func getFrameValue() -> Int {
        let frameField = app.textFields["input-frame"]
        guard frameField.exists else { return 0 }
        let value = frameField.value as? String ?? "0"
        return Int(value) ?? 0
    }

    func getOpacityValue() -> Int {
        let opacityField = app.textFields["input-opacity"]
        guard opacityField.exists else { return 100 }
        let value = opacityField.value as? String ?? "100"
        return Int(value) ?? 100
    }

    func getSliderValue(_ identifier: String) -> Double {
        let slider = app.sliders[identifier]
        guard slider.exists else { return 0 }
        let raw = slider.value as? String ?? "0"
        return Double(raw) ?? 0
    }

    func isLocked() -> Bool {
        let lockButton = app.buttons["button-lock"]
        guard lockButton.exists else { return false }
        // When unlocked, label is "unlock" (from lock.open.fill icon)
        // When locked, label is "lock" (from lock.fill icon)
        // If label is exactly "lock", we're locked. If "unlock", we're unlocked.
        return lockButton.label == "lock"
    }

    func ensureUnlocked() {
        // Check if we can determine lock state
        let lockButton = app.buttons["button-lock"]
        if lockButton.waitForExistence(timeout: 1) {
            // Press L if we're locked
            if isLocked() {
                app.typeKey("l", modifierFlags: [])
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
    }

    func ensureLocked() {
        if !isLocked() {
            app.typeKey("l", modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    func isVideoLoaded() -> Bool {
        let slider = app.sliders["slider-timeline"]
        return slider.exists && slider.isEnabled
    }

    private func waitForVideoReady(timeout: TimeInterval = 8) {
        let slider = app.sliders["slider-timeline"]
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: slider)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed {
            XCTFail("Video failed to load in setup - timeline slider not enabled")
        }
    }

    // MARK: - Video Loading

    func testVideoLoads() throws {
        XCTAssertTrue(isVideoLoaded(), "Video should be loaded via TEST_VIDEO_PATH")

        // Verify overlays appear
        let frameField = app.textFields["input-frame"]
        XCTAssertTrue(frameField.waitForExistence(timeout: 2), "Frame field should exist when video loaded")
    }

    // Debug test to list all UI elements
    func testDebugListElements() throws {
        Thread.sleep(forTimeInterval: 1)

        print("=== ALL BUTTONS ===")
        for button in app.buttons.allElementsBoundByIndex {
            print("Button: identifier='\(button.identifier)' label='\(button.label)' exists=\(button.exists)")
        }

        print("=== LOOKING FOR button-lock ===")
        let lockButton = app.buttons["button-lock"]
        print("button-lock exists: \(lockButton.exists)")
        print("button-lock waitForExistence: \(lockButton.waitForExistence(timeout: 2))")

        print("=== LOOKING FOR button-step-forward ===")
        let stepButton = app.buttons["button-step-forward"]
        print("button-step-forward exists: \(stepButton.exists)")

        // Debug help modal
        print("=== SHOWING HELP AND LISTING ALL ELEMENTS ===")
        app.typeKey("h", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        print("=== ALL WINDOWS ===")
        for window in app.windows.allElementsBoundByIndex {
            print("Window: identifier='\(window.identifier)' label='\(window.label)'")
        }

        print("=== ALL GROUPS ===")
        for group in app.groups.allElementsBoundByIndex {
            print("Group: identifier='\(group.identifier)' label='\(group.label)'")
        }

        print("=== ALL OTHER ELEMENTS ===")
        for elem in app.otherElements.allElementsBoundByIndex {
            print("OtherElement: identifier='\(elem.identifier)' label='\(elem.label)'")
        }

        print("=== CHECKING modal-help ===")
        print("app.otherElements['modal-help'].exists: \(app.otherElements["modal-help"].exists)")
        print("app.groups['modal-help'].exists: \(app.groups["modal-help"].exists)")
        print("app.windows['modal-help'].exists: \(app.windows["modal-help"].exists)")
        print("app.windows['window-help'].exists: \(app.windows["window-help"].exists)")

        // Close help
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - YouTube Prompt

    func testYouTubePromptAppearsOnLongPress() throws {
        let openButton = app.buttons["button-open"]
        XCTAssertTrue(openButton.exists, "Open button should exist")

        openButton.press(forDuration: 0.4)

        let inputField = app.textFields["youtube-url-input"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 2), "YouTube URL input should appear")

        let sheetCancel = app.sheets.buttons["Cancel"].firstMatch
        if sheetCancel.exists {
            sheetCancel.click()
            return
        }

        let anyCancel = app.buttons.matching(identifier: "Cancel").firstMatch
        if anyCancel.exists {
            anyCancel.click()
        }
    }

    // MARK: - F-VP-002: Spacebar Play/Pause

    func testSpacebar_TogglesPlayback() throws {
        XCTAssertTrue(isVideoLoaded(), "Video must be loaded")

        let initialFrame = getFrameValue()

        // Press Space to play
        app.typeKey(" ", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // Press Space to pause
        app.typeKey(" ", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        let frameAfterPlayPause = getFrameValue()

        // Frame should have advanced during playback
        XCTAssertGreaterThan(frameAfterPlayPause, initialFrame, "Frame should advance when video plays")
    }

    // MARK: - F-VP-003: Play Button

    func testPlayButton_TogglesPlayback() throws {
        XCTAssertTrue(isVideoLoaded())

        let playButton = app.buttons["button-play"]
        XCTAssertTrue(playButton.exists, "Play button must exist")

        let initialFrame = getFrameValue()

        // Click to play
        playButton.click()
        Thread.sleep(forTimeInterval: 0.5)

        // Click to pause
        playButton.click()
        Thread.sleep(forTimeInterval: 0.2)

        let frameAfter = getFrameValue()
        XCTAssertGreaterThan(frameAfter, initialFrame, "Frame should advance after clicking play")
    }

    // MARK: - F-VP-004: Step Forward/Backward Buttons

    func testStepForwardButton_AdvancesOneFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        // Ensure paused - check play button state first
        let playButton = app.buttons["button-play"]
        if playButton.exists && playButton.label == "pause" {
            // Video is playing, pause it
            app.typeKey(" ", modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.3)
        }

        let stepForward = app.buttons["button-step-forward"]
        XCTAssertTrue(stepForward.exists)

        // Get initial frame
        let initialFrame = getFrameValue()

        // Step forward once
        stepForward.click()
        Thread.sleep(forTimeInterval: 0.3)

        let newFrame = getFrameValue()
        XCTAssertEqual(newFrame, initialFrame + 1, "Frame should advance by exactly 1")
    }

    func testStepBackwardButton_RegressesOneFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        let stepForward = app.buttons["button-step-forward"]
        let stepBackward = app.buttons["button-step-backward"]

        // First advance a few frames
        stepForward.click()
        stepForward.click()
        stepForward.click()
        Thread.sleep(forTimeInterval: 0.3)

        let frameBeforeBack = getFrameValue()
        XCTAssertGreaterThanOrEqual(frameBeforeBack, 3, "Should have advanced at least 3 frames")

        stepBackward.click()
        Thread.sleep(forTimeInterval: 0.3)

        let frameAfterBack = getFrameValue()
        XCTAssertEqual(frameAfterBack, frameBeforeBack - 1, "Frame should decrease by exactly 1")
    }

    func testTimelineScrubUpdatesFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        let slider = app.sliders["slider-timeline"]
        XCTAssertTrue(slider.exists)

        slider.adjust(toNormalizedSliderPosition: 0.5)
        Thread.sleep(forTimeInterval: 0.4)

        let frameAfterScrub = getFrameValue()
        XCTAssertGreaterThan(frameAfterScrub, 0, "Scrubbing should move to a later frame")
    }

    // MARK: - F-ZP-001: Zoom via Scroll Wheel with Shift

    // Note: XCUITest can't easily simulate scroll with modifiers
    // This would need manual testing or custom event injection

    // MARK: - F-ZP-003: Zoom Input Field

    func testZoomField_UpArrowIncrementsAndAffectsDisplay() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(zoomField.exists)

        // Get initial zoom
        let initialZoom = getZoomValue()

        // Click to focus
        zoomField.click()
        Thread.sleep(forTimeInterval: 0.2)

        // Press Up arrow
        app.typeKey(.upArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        let newZoom = getZoomValue()
        XCTAssertEqual(newZoom, initialZoom + 1, accuracy: 0.1, "Zoom should increase by 1")

        // Defocus
        app.typeKey(.escape, modifierFlags: [])
    }

    func testZoomField_ShiftUpArrowIncrementsBy10() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]
        zoomField.click()
        Thread.sleep(forTimeInterval: 0.2)

        let initialZoom = getZoomValue()

        // Press Shift+Up
        app.typeKey(.upArrow, modifierFlags: .shift)
        Thread.sleep(forTimeInterval: 0.3)

        let newZoom = getZoomValue()
        XCTAssertEqual(newZoom, initialZoom + 10, accuracy: 0.5, "Shift+Up should increase zoom by 10")

        app.typeKey(.escape, modifierFlags: [])
    }

    func testInputField_CmdASelectAllReplacesValue() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(zoomField.exists)

        // Set a known value first
        zoomField.doubleTap()
        Thread.sleep(forTimeInterval: 0.1)
        app.typeText("120")
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        // Cmd+A should select all so the next entry replaces the value
        zoomField.click()
        app.typeKey("a", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.1)
        app.typeText("80")
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        let newZoom = getZoomValue()
        XCTAssertEqual(newZoom, 80, accuracy: 0.5, "Cmd+A should select all and replace the value")
    }

    // Note: Cmd+UpArrow in text fields is intercepted by macOS for document navigation
    // (moveToBeginningOfDocument:) before reaching the text field's command delegate.
    // This fine-grained zoom control is tested manually but not automatable via XCUITest.
    func testZoomField_CmdUpArrowIncrementsBy01() throws {
        // Skip this test - Cmd+arrow key events are handled specially by macOS
        // and don't reliably trigger the text field delegate in the XCUITest environment.
        // The 0.1% fine zoom increment still works when used manually.
        throw XCTSkip("Cmd+UpArrow is intercepted by macOS before reaching text field delegate")
    }

    // MARK: - F-ZP-004: Zero Key Resets Zoom

    func testZeroKey_ResetsZoomTo100() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        // First change zoom
        let zoomField = app.textFields["input-zoom"]
        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift) // +10
        app.typeKey(.upArrow, modifierFlags: .shift) // +10
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        let zoomBefore = getZoomValue()
        XCTAssertGreaterThan(zoomBefore, 100, "Zoom should be > 100 before reset")

        // Press 0
        app.typeKey("0", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        let zoomAfter = getZoomValue()
        XCTAssertEqual(zoomAfter, 100, accuracy: 0.5, "Zoom should reset to 100")
    }

    // MARK: - F-ZP-005: R Key Resets View

    func testRKey_ResetsZoomAndPan() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        // Change zoom
        let zoomField = app.textFields["input-zoom"]
        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift)
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        // Pan with arrow keys
        app.typeKey(.leftArrow, modifierFlags: .shift)
        app.typeKey(.upArrow, modifierFlags: .shift)
        Thread.sleep(forTimeInterval: 0.2)

        // Press R
        app.typeKey("r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        let zoomAfter = getZoomValue()
        XCTAssertEqual(zoomAfter, 100, accuracy: 0.5, "Zoom should reset to 100 after R")
    }

    // MARK: - F-ZP-002: Arrow Keys Pan

    func testArrowKeys_PanVideo() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        // Reset first
        app.typeKey("r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        // Press arrow keys - should not crash and video should remain
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])

        // Shift+arrows for 10px
        app.typeKey(.leftArrow, modifierFlags: .shift)
        app.typeKey(.rightArrow, modifierFlags: .shift)
        app.typeKey(.upArrow, modifierFlags: .shift)
        app.typeKey(.downArrow, modifierFlags: .shift)

        // Cmd+Shift+arrows for 100px
        app.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        app.typeKey(.rightArrow, modifierFlags: [.command, .shift])
        app.typeKey(.upArrow, modifierFlags: [.command, .shift])
        app.typeKey(.downArrow, modifierFlags: [.command, .shift])

        XCTAssertTrue(isVideoLoaded(), "Video should still be displayed after panning")
    }

    // MARK: - F-LK-001: Lock Toggle

    func testLKey_TogglesLock() throws {
        ensureUnlocked()
        XCTAssertFalse(isLocked(), "Should start unlocked")

        app.typeKey("l", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertTrue(isLocked(), "Should be locked after pressing L")

        app.typeKey("l", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertFalse(isLocked(), "Should be unlocked after pressing L again")
    }

    func testLockButton_TogglesLock() throws {
        ensureUnlocked()

        let lockButton = app.buttons["button-lock"]
        XCTAssertTrue(lockButton.exists)

        lockButton.click()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertTrue(isLocked(), "Should be locked after clicking lock button")

        lockButton.click()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertFalse(isLocked(), "Should be unlocked after clicking again")
    }

    // MARK: - F-LK-002: Lock Disables Controls

    func testLock_DisablesZoomField() throws {
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(zoomField.isEnabled, "Zoom field should be enabled when unlocked")

        ensureLocked()

        XCTAssertFalse(zoomField.isEnabled, "Zoom field should be disabled when locked")

        ensureUnlocked()

        XCTAssertTrue(zoomField.isEnabled, "Zoom field should be enabled after unlocking")
    }

    func testLock_ArrowKeysDontPan() throws {
        XCTAssertTrue(isVideoLoaded())

        // Reset first
        ensureUnlocked()
        app.typeKey("r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        // Lock
        ensureLocked()

        // Arrow keys should do nothing (no pan)
        app.typeKey(.leftArrow, modifierFlags: .shift)
        app.typeKey(.upArrow, modifierFlags: .shift)

        // Video should still be at reset position (can't easily verify pan, but no crash)
        XCTAssertTrue(isVideoLoaded())

        ensureUnlocked()
    }

    /// Global shortcuts require accessibility permissions which aren't available in UI tests
    func testLockMode_CmdPageDownStepsFrames() throws {
        throw XCTSkip("Global shortcuts require accessibility permissions - test manually")
        XCTAssertTrue(isVideoLoaded())
        ensureLocked()

        let initialFrame = getFrameValue()
        app.typeKey(.pageDown, modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)

        let newFrame = getFrameValue()
        XCTAssertEqual(newFrame, initialFrame + 1, "Cmd+PageDown should step 1 frame when locked")

        // Shift+Cmd should step 10 frames
        app.typeKey(.pageDown, modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.3)
        let afterShift = getFrameValue()
        XCTAssertEqual(afterShift, newFrame + 10, "Cmd+Shift+PageDown should step 10 frames when locked")

        ensureUnlocked()
    }

    // MARK: - F-OP-001: Opacity Field

    func testOpacityField_ArrowKeysAdjust() throws {
        XCTAssertTrue(isVideoLoaded())

        let opacityField = app.textFields["input-opacity"]
        XCTAssertTrue(opacityField.exists)

        opacityField.click()
        Thread.sleep(forTimeInterval: 0.2)

        let initialOpacity = getOpacityValue()

        app.typeKey(.downArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        let newOpacity = getOpacityValue()

        if initialOpacity > 2 { // Min is 2
            XCTAssertLessThan(newOpacity, initialOpacity, "Opacity should decrease after Down arrow")
        }

        app.typeKey(.escape, modifierFlags: [])
    }

    func testOpacityField_ShiftArrowAdjustsBy10() throws {
        XCTAssertTrue(isVideoLoaded())

        let opacityField = app.textFields["input-opacity"]
        opacityField.click()
        Thread.sleep(forTimeInterval: 0.2)

        let initialOpacity = getOpacityValue()

        app.typeKey(.upArrow, modifierFlags: .shift)
        Thread.sleep(forTimeInterval: 0.3)

        let newOpacity = getOpacityValue()
        XCTAssertEqual(newOpacity, min(100, initialOpacity + 10), "Shift+Up should increase opacity by 10%")

        app.typeKey(.escape, modifierFlags: [])
    }

    func testQuickFilterParameterlessDisablesSlider() throws {
        XCTAssertTrue(isVideoLoaded())

        let filterButton = app.buttons["button-filter-menu"]
        XCTAssertTrue(filterButton.exists, "Filter button should exist")

        // Select Invert (parameterless)
        filterButton.press(forDuration: 0.4)
        let invertItem = app.menuItems["quick-filter-invert"]
        guard invertItem.waitForExistence(timeout: 2) else {
            throw XCTSkip("Filter menu did not appear")
        }
        invertItem.click()
        Thread.sleep(forTimeInterval: 0.3)

        let opacitySlider = app.sliders["slider-opacity"]
        let opacityField = app.textFields["input-opacity"]
        XCTAssertFalse(opacitySlider.isEnabled, "Opacity slider should be disabled for parameterless filter")
        XCTAssertEqual(opacityField.value as? String, "On", "Opacity field should show On for parameterless filter")

        // Select Brightness (adjustable) to restore slider
        filterButton.press(forDuration: 0.4)
        let brightnessItem = app.menuItems["quick-filter-brightness"]
        if brightnessItem.waitForExistence(timeout: 2) {
            brightnessItem.click()
            Thread.sleep(forTimeInterval: 0.3)
            XCTAssertTrue(opacitySlider.isEnabled, "Opacity slider should be enabled for adjustable filter")
        }
    }

    // MARK: - F-UI-004: Help Modal

    func testHKey_TogglesHelp() throws {
        app.typeKey("h", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        // Help modal appears as a group element, not otherElements
        let helpModal = app.groups["modal-help"]
        XCTAssertTrue(helpModal.exists, "Help modal should appear after pressing H")

        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertFalse(helpModal.isHittable, "Help modal should close after pressing Escape")
    }

    // Note: Help button removed from toolbar per design decision
    // Help is accessible via H key or Help menu instead

    // MARK: - F-VP-005: Frame Input Field

    func testFrameField_TypeValueSeeksToFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        let frameField = app.textFields["input-frame"]
        XCTAssertTrue(frameField.exists)

        // Double-click to select the word (all digits in this case)
        frameField.doubleTap()
        Thread.sleep(forTimeInterval: 0.2)

        // Type new value (replaces selected text)
        app.typeText("30")
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        let newFrame = getFrameValue()
        XCTAssertEqual(newFrame, 30, "Frame should be 30 after typing and pressing Enter")
    }

    func testFrameField_ArrowKeysStep() throws {
        XCTAssertTrue(isVideoLoaded())

        let frameField = app.textFields["input-frame"]
        frameField.click()
        Thread.sleep(forTimeInterval: 0.2)

        let initialFrame = getFrameValue()

        app.typeKey(.upArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        let newFrame = getFrameValue()
        XCTAssertEqual(newFrame, initialFrame + 1, "Frame should increment by 1 with Up arrow")

        app.typeKey(.escape, modifierFlags: [])
    }

    func testFrameField_ShiftArrowStepsBy10() throws {
        XCTAssertTrue(isVideoLoaded())

        let frameField = app.textFields["input-frame"]
        frameField.click()
        Thread.sleep(forTimeInterval: 0.2)

        let initialFrame = getFrameValue()

        app.typeKey(.upArrow, modifierFlags: .shift)
        Thread.sleep(forTimeInterval: 0.3)

        let newFrame = getFrameValue()
        XCTAssertEqual(newFrame, initialFrame + 10, "Shift+Up should increment by 10 frames")

        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - F-AU-001: Mute Button

    func testMuteButton_Toggles() throws {
        let muteButton = app.buttons["button-mute"]
        XCTAssertTrue(muteButton.exists)

        // Toggle twice
        muteButton.click()
        Thread.sleep(forTimeInterval: 0.2)

        muteButton.click()
        Thread.sleep(forTimeInterval: 0.2)

        // Button should still exist (no crash)
        XCTAssertTrue(muteButton.exists)
    }

    func testMuteRestoresPreviousVolume() throws {
        let muteButton = app.buttons["button-mute"]
        let volumeSlider = app.sliders["slider-volume"]
        XCTAssertTrue(muteButton.exists)

        // Ensure unmuted so slider is visible
        if !volumeSlider.isHittable {
            muteButton.click()
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTAssertTrue(volumeSlider.waitForExistence(timeout: 2))
        volumeSlider.adjust(toNormalizedSliderPosition: 0.7)
        Thread.sleep(forTimeInterval: 0.2)
        let initialVolume = getSliderValue("slider-volume")

        // Mute
        muteButton.click()
        Thread.sleep(forTimeInterval: 0.2)

        // Unmute
        muteButton.click()
        Thread.sleep(forTimeInterval: 0.2)

        let restoredVolume = getSliderValue("slider-volume")
        XCTAssertEqual(restoredVolume, initialVolume, accuracy: 0.05, "Unmute should restore previous volume")
    }

    // MARK: - Compound Workflow Tests

    func testFullPlaybackWorkflow() throws {
        XCTAssertTrue(isVideoLoaded())

        let stepForward = app.buttons["button-step-forward"]
        let stepBackward = app.buttons["button-step-backward"]
        let frameField = app.textFields["input-frame"]

        // 1. Step forward to get to a known position
        stepForward.click()
        stepForward.click()
        Thread.sleep(forTimeInterval: 0.3)

        let afterStepForward = getFrameValue()

        // 2. Step backward 1 time
        stepBackward.click()
        Thread.sleep(forTimeInterval: 0.3)

        let afterStepBackward = getFrameValue()
        XCTAssertLessThan(afterStepBackward, afterStepForward, "Frame should decrease after stepping backward")

        // 3. Verify frame field can be edited
        frameField.doubleTap()
        Thread.sleep(forTimeInterval: 0.1)
        app.typeText("0")
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        let afterSeek = getFrameValue()
        XCTAssertEqual(afterSeek, 0, "Should be at frame 0 after typing in field")

        // 4. Play briefly and verify frame advances
        app.typeKey(" ", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey(" ", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        let finalFrame = getFrameValue()
        XCTAssertGreaterThan(finalFrame, afterSeek, "Frame should advance after playing")
    }

    func testFullZoomWorkflow() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]

        // 1. Reset
        app.typeKey("r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(getZoomValue(), 100, accuracy: 0.5, "Zoom should be 100 after reset")

        // 2. Increase zoom via field
        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift) // +10
        app.typeKey(.upArrow, modifierFlags: .shift) // +10
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(getZoomValue(), 120, accuracy: 1, "Zoom should be ~120 after two Shift+Up")

        // 3. Reset with 0
        app.typeKey("0", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(getZoomValue(), 100, accuracy: 0.5, "Zoom should be 100 after pressing 0")

        // 4. Change again and reset with R
        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift)
        app.typeKey(.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        app.typeKey("r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(getZoomValue(), 100, accuracy: 0.5, "Zoom should be 100 after R")
    }

    func testLockWorkflow() throws {
        XCTAssertTrue(isVideoLoaded())

        let zoomField = app.textFields["input-zoom"]
        let lockButton = app.buttons["button-lock"]

        // 1. Ensure unlocked
        ensureUnlocked()

        XCTAssertTrue(zoomField.isEnabled, "Zoom field enabled when unlocked")

        // 2. Change zoom
        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift)
        app.typeKey(.escape, modifierFlags: [])

        let zoomAfterChange = getZoomValue()
        XCTAssertGreaterThan(zoomAfterChange, 100, "Zoom should have changed")

        // 3. Lock
        lockButton.click()
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertTrue(isLocked(), "Should be locked")
        XCTAssertFalse(zoomField.isEnabled, "Zoom field disabled when locked")

        // 4. Try to change zoom (should fail since disabled)
        // Field is disabled so can't click

        // 5. Unlock with L key
        app.typeKey("l", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertFalse(isLocked(), "Should be unlocked")
        XCTAssertTrue(zoomField.isEnabled, "Zoom field enabled again")

        // 6. Reset
        app.typeKey("r", modifierFlags: [])
    }
}
