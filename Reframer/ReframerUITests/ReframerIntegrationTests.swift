import XCTest

/// Comprehensive integration tests with video loaded.
/// Each test launches with its own sandbox-staged fixture and restores a known
/// UI state, so execution order cannot change the result.
final class ReframerIntegrationTests: XCTestCase {

    private var app: XCUIApplication!
    private var fixtureURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixtureURL = UITestVideoLoader.fixtureURL(
            named: "test-video",
            relativeTo: #filePath
        )
        app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-VideoOverlay.quickFilter", "__UITEST_NONE__",
            "-VideoOverlay.opacity", "1.0",
            "-VideoOverlay.muted", "YES",
            "-VideoOverlay.volume", "0.5",
            "-VideoOverlay.lastVolume", "0.5"
        ]
        app.launch()
        XCTAssertTrue(
            UITestVideoLoader.open(fixtureURL, in: app),
            "Fixture should open through Launch Services"
        )
        waitForVideoReady()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
        fixtureURL = nil
    }

    // MARK: - Helpers

    func getZoomValue() -> Double {
        let zoomField = app.textFields["input-zoom"]
        return numericValue(of: zoomField) ?? 100
    }

    func getFrameValue() -> Int {
        let frameField = app.textFields["input-frame"]
        return Int((numericValue(of: frameField) ?? 0).rounded())
    }

    func getOpacityValue() -> Int {
        let opacityField = app.textFields["input-opacity"]
        return Int((numericValue(of: opacityField) ?? 100).rounded())
    }

    func getSliderValue(_ identifier: String) -> Double {
        numericValue(of: app.sliders[identifier]) ?? 0
    }

    private func numericValue(of element: XCUIElement) -> Double? {
        if let number = element.value as? NSNumber {
            return number.doubleValue
        }
        guard let rawValue = element.value as? String else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPercent = trimmed.hasSuffix("%")
        let numericText = trimmed
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(numericText) else { return nil }
        return isPercent && element.elementType == .slider ? value / 100 : value
    }

    func isLocked() -> Bool {
        let lockButton = app.buttons["button-lock"]
        guard lockButton.exists else { return false }
        return lockButton.value as? String == "Locked"
    }

    func ensureUnlocked() {
        let lockButton = app.buttons["button-lock"]
        if lockButton.waitForExistence(timeout: 1) {
            if isLocked() {
                app.typeKey("l", modifierFlags: [])
                XCTAssertTrue(
                    waitForValue("Unlocked", in: lockButton),
                    "L should unlock the overlay"
                )
            }
        }
    }

    func ensureLocked() {
        if !isLocked() {
            app.typeKey("l", modifierFlags: [])
            XCTAssertTrue(
                waitForValue("Locked", in: app.buttons["button-lock"]),
                "L should lock the overlay"
            )
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

    private func waitForValue(
        _ expected: String,
        in element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNumericValue(
        _ expected: Double,
        in element: XCUIElement,
        accuracy: Double = 0.05,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard let value = self.numericValue(of: element) else { return false }
            return abs(value - expected) <= accuracy
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNumericChange(
        from initial: Double,
        in element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard let value = self.numericValue(of: element) else { return false }
            return abs(value - initial) > 0.001
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForEnabled(
        _ expected: Bool,
        element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == %@", NSNumber(value: expected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForHittable(
        _ expected: Bool,
        element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "isHittable == %@", NSNumber(value: expected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Video Loading

    func testVideoLoads() throws {
        XCTAssertTrue(isVideoLoaded(), "Video should be loaded through Launch Services")

        // Verify overlays appear
        let frameField = app.textFields["input-frame"]
        XCTAssertTrue(frameField.waitForExistence(timeout: 2), "Frame field should exist when video loaded")
        XCTAssertTrue(
            app.staticTexts["status-frame"].waitForExistence(timeout: 2),
            "Ready video should expose frame status"
        )
        XCTAssertTrue(app.staticTexts["status-zoom"].exists)
        XCTAssertTrue(app.staticTexts["status-lock"].exists)
    }

    // MARK: - F-VP-002: Spacebar Play/Pause

    func testSpacebar_TogglesPlayback() throws {
        XCTAssertTrue(isVideoLoaded(), "Video must be loaded")

        let initialFrame = getFrameValue()
        let frameField = app.textFields["input-frame"]

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(
            waitForNumericChange(from: Double(initialFrame), in: frameField),
            "Space should start playback and advance the frame"
        )
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(waitForValue("Paused", in: app.buttons["button-play"]))
    }

    // MARK: - F-VP-003: Play Button

    func testPlayButton_TogglesPlayback() throws {
        XCTAssertTrue(isVideoLoaded())

        let playButton = app.buttons["button-play"]
        XCTAssertTrue(playButton.exists, "Play button must exist")

        let initialFrame = getFrameValue()
        let frameField = app.textFields["input-frame"]

        playButton.click()
        XCTAssertTrue(
            waitForNumericChange(from: Double(initialFrame), in: frameField),
            "Clicking Play should advance the frame"
        )
        playButton.click()
        XCTAssertTrue(waitForValue("Paused", in: playButton))
    }

    // MARK: - F-VP-004: Step Forward/Backward Buttons

    func testStepForwardButton_AdvancesOneFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        // Ensure paused - check play button state first
        let playButton = app.buttons["button-play"]
        if playButton.exists && playButton.value as? String == "Playing" {
            app.typeKey(" ", modifierFlags: [])
            XCTAssertTrue(waitForValue("Paused", in: playButton))
        }

        let stepForward = app.buttons["button-step-forward"]
        XCTAssertTrue(stepForward.exists)

        let initialFrame = getFrameValue()

        stepForward.click()
        XCTAssertTrue(
            waitForNumericValue(
                Double(initialFrame + 1),
                in: app.textFields["input-frame"]
            ),
            "Frame should advance by exactly 1"
        )
    }

    func testStepBackwardButton_RegressesOneFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        let stepForward = app.buttons["button-step-forward"]
        let stepBackward = app.buttons["button-step-backward"]

        // First advance a few frames
        stepForward.click()
        stepForward.click()
        stepForward.click()
        XCTAssertTrue(
            waitForNumericValue(3, in: app.textFields["input-frame"]),
            "Three forward steps should reach frame 3"
        )

        let frameBeforeBack = getFrameValue()
        XCTAssertGreaterThanOrEqual(frameBeforeBack, 3, "Should have advanced at least 3 frames")

        stepBackward.click()
        XCTAssertTrue(
            waitForNumericValue(
                Double(frameBeforeBack - 1),
                in: app.textFields["input-frame"]
            ),
            "Frame should decrease by exactly 1"
        )
    }

    func testTimelineScrubUpdatesFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        let slider = app.sliders["slider-timeline"]
        XCTAssertTrue(slider.exists)

        let initialFrame = getFrameValue()
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(
            waitForNumericChange(
                from: Double(initialFrame),
                in: app.textFields["input-frame"]
            ),
            "Scrubbing should move to a different decoded frame"
        )
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

        let initialZoom = getZoomValue()

        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(initialZoom + 1, in: zoomField),
            "Zoom should increase by 1"
        )

        // Defocus
        app.typeKey(.escape, modifierFlags: [])
    }

    func testZoomField_ShiftUpArrowIncrementsBy10() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]
        zoomField.click()

        let initialZoom = getZoomValue()

        app.typeKey(.upArrow, modifierFlags: .shift)
        XCTAssertTrue(
            waitForNumericValue(initialZoom + 10, in: zoomField, accuracy: 0.5),
            "Shift+Up should increase zoom by 10"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    func testInputField_CmdASelectAllReplacesValue() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(zoomField.exists)

        zoomField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("120")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForNumericValue(120, in: zoomField))

        zoomField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("80")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(80, in: zoomField, accuracy: 0.5),
            "Cmd+A should select all and replace the value"
        )
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
        XCTAssertTrue(
            waitForNumericValue(120, in: zoomField, accuracy: 0.5),
            "Two Shift-Up events should set 120% before reset"
        )

        app.typeKey("0", modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(100, in: zoomField, accuracy: 0.5),
            "0 should reset zoom to 100%"
        )
    }

    // MARK: - F-ZP-005: R Key Resets View

    func testRKey_ResetsObservableZoom() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        // Change zoom
        let zoomField = app.textFields["input-zoom"]
        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNumericValue(110, in: zoomField, accuracy: 0.5))

        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(100, in: zoomField, accuracy: 0.5),
            "R should reset zoom to 100%"
        )
    }

    // MARK: - F-LK-001: Lock Toggle

    func testLKey_TogglesLock() throws {
        ensureUnlocked()
        XCTAssertFalse(isLocked(), "Should start unlocked")

        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(waitForValue("Locked", in: app.buttons["button-lock"]))

        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(waitForValue("Unlocked", in: app.buttons["button-lock"]))
    }

    func testLockButton_TogglesLock() throws {
        ensureUnlocked()

        let lockButton = app.buttons["button-lock"]
        XCTAssertTrue(lockButton.exists)

        lockButton.click()
        XCTAssertTrue(waitForValue("Locked", in: lockButton))

        lockButton.click()
        XCTAssertTrue(waitForValue("Unlocked", in: lockButton))
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

    /// The app-active path exercises the same command resolver without leaving
    /// the test process.
    func testLockMode_CmdPageDownStepsFrames() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureLocked()

        let initialFrame = getFrameValue()
        app.typeKey(.pageDown, modifierFlags: .command)
        let frameField = app.textFields["input-frame"]
        XCTAssertTrue(
            waitForNumericValue(Double(initialFrame + 1), in: frameField),
            "Cmd+PageDown should step 1 frame when locked"
        )

        app.typeKey(.pageDown, modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForNumericValue(Double(initialFrame + 11), in: frameField),
            "Cmd+Shift+PageDown should step 10 frames when locked"
        )

        ensureUnlocked()
    }

    // MARK: - F-OP-001: Opacity Field

    func testOpacityField_ArrowKeysAdjust() throws {
        XCTAssertTrue(isVideoLoaded())

        let opacityField = app.textFields["input-opacity"]
        XCTAssertTrue(opacityField.exists)

        opacityField.click()
        let initialOpacity = getOpacityValue()

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(
                Double(max(2, initialOpacity - 1)),
                in: opacityField
            ),
            "Down should decrease opacity by one percentage point"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    func testOpacityField_ShiftArrowAdjustsBy10() throws {
        XCTAssertTrue(isVideoLoaded())

        let opacityField = app.textFields["input-opacity"]
        opacityField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("50")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForNumericValue(50, in: opacityField))
        app.typeKey(.upArrow, modifierFlags: .shift)
        XCTAssertTrue(
            waitForNumericValue(60, in: opacityField),
            "Shift+Up should increase opacity by 10 percentage points"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    func testQuickFilterParameterlessDisablesSlider() throws {
        XCTAssertTrue(isVideoLoaded())

        let filterButton = app.buttons["button-filter-menu"]
        XCTAssertTrue(filterButton.exists, "Filter button should exist")

        // Select Invert (parameterless)
        filterButton.click()
        let invertItem = app.menuItems["quick-filter-invert"]
        XCTAssertTrue(
            invertItem.waitForExistence(timeout: 2),
            "The quick-filter button should present the Invert menu item"
        )
        invertItem.click()

        let opacitySlider = app.sliders["slider-opacity"]
        let opacityField = app.textFields["input-opacity"]
        XCTAssertTrue(
            waitForEnabled(false, element: opacitySlider),
            "Opacity slider should be disabled for a parameterless filter"
        )
        XCTAssertTrue(
            waitForValue("On", in: opacityField),
            "Opacity field should show On for a parameterless filter"
        )

        // Select Brightness (adjustable) to restore slider
        filterButton.click()
        let brightnessItem = app.menuItems["quick-filter-brightness"]
        XCTAssertTrue(
            brightnessItem.waitForExistence(timeout: 2),
            "The quick-filter button should present the Brightness menu item"
        )
        brightnessItem.click()
        XCTAssertTrue(
            waitForEnabled(true, element: opacitySlider),
            "Opacity slider should be enabled for an adjustable filter"
        )
    }

    // MARK: - F-UI-004: Help Modal

    func testHKey_TogglesHelp() throws {
        app.typeKey("h", modifierFlags: [])

        let helpModal = app.groups["modal-help"]
        XCTAssertTrue(
            helpModal.waitForExistence(timeout: 3),
            "Help modal should appear after pressing H"
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForHittable(false, element: helpModal),
            "Help modal should close after pressing Escape"
        )
    }

    // Note: Help button removed from toolbar per design decision
    // Help is accessible via H key or Help menu instead

    // MARK: - F-VP-005: Frame Input Field

    func testFrameField_TypeValueSeeksToFrame() throws {
        XCTAssertTrue(isVideoLoaded())

        let frameField = app.textFields["input-frame"]
        XCTAssertTrue(frameField.exists)

        frameField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("30")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(30, in: frameField),
            "Frame should be 30 after typing and pressing Return"
        )
    }

    func testFrameField_ArrowKeysStep() throws {
        XCTAssertTrue(isVideoLoaded())

        let frameField = app.textFields["input-frame"]
        frameField.click()

        let initialFrame = getFrameValue()

        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(Double(initialFrame + 1), in: frameField),
            "Frame should increment by 1 with Up"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    func testFrameField_ShiftArrowStepsBy10() throws {
        XCTAssertTrue(isVideoLoaded())

        let frameField = app.textFields["input-frame"]
        frameField.click()

        let initialFrame = getFrameValue()

        app.typeKey(.upArrow, modifierFlags: .shift)
        XCTAssertTrue(
            waitForNumericValue(Double(initialFrame + 10), in: frameField),
            "Shift+Up should increment by 10 frames"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - F-AU-001: Mute Button

    func testMuteButton_Toggles() throws {
        let muteButton = app.buttons["button-mute"]
        XCTAssertTrue(muteButton.exists)

        muteButton.click()
        XCTAssertTrue(waitForValue("Audible", in: muteButton))
        muteButton.click()
        XCTAssertTrue(waitForValue("Muted", in: muteButton))
    }

    func testMuteRestoresPreviousVolume() throws {
        let muteButton = app.buttons["button-mute"]
        let volumeSlider = app.sliders["slider-volume"]
        XCTAssertTrue(muteButton.exists)

        // Ensure unmuted so slider is visible
        if !volumeSlider.isHittable {
            muteButton.click()
        }

        XCTAssertTrue(volumeSlider.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForHittable(true, element: volumeSlider))
        volumeSlider.adjust(toNormalizedSliderPosition: 0.7)
        XCTAssertTrue(
            waitForNumericChange(from: 0.5, in: volumeSlider),
            "Adjusting the volume slider should change its value"
        )
        let initialVolume = getSliderValue("slider-volume")

        muteButton.click()
        XCTAssertTrue(waitForValue("Muted", in: muteButton))
        muteButton.click()
        XCTAssertTrue(waitForValue("Audible", in: muteButton))
        XCTAssertTrue(waitForHittable(true, element: volumeSlider))

        let restoredVolume = getSliderValue("slider-volume")
        XCTAssertEqual(restoredVolume, initialVolume, accuracy: 0.05, "Unmute should restore previous volume")
    }

    // MARK: - Compound Workflow Tests

    func testFullPlaybackWorkflow() throws {
        XCTAssertTrue(isVideoLoaded())

        let stepForward = app.buttons["button-step-forward"]
        let stepBackward = app.buttons["button-step-backward"]
        let frameField = app.textFields["input-frame"]

        stepForward.click()
        stepForward.click()
        XCTAssertTrue(waitForNumericValue(2, in: frameField))

        stepBackward.click()
        XCTAssertTrue(
            waitForNumericValue(1, in: frameField),
            "A backward step should move from frame 2 to frame 1"
        )

        frameField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("0")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(0, in: frameField),
            "Entering 0 should seek to the first frame"
        )

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(
            waitForNumericChange(from: 0, in: frameField),
            "Playback should advance after the exact seek"
        )
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(waitForValue("Paused", in: app.buttons["button-play"]))
    }

    func testFullZoomWorkflow() throws {
        XCTAssertTrue(isVideoLoaded())
        ensureUnlocked()

        let zoomField = app.textFields["input-zoom"]

        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(100, in: zoomField),
            "Zoom should be 100 after reset"
        )

        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift) // +10
        app.typeKey(.upArrow, modifierFlags: .shift) // +10
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(120, in: zoomField, accuracy: 1),
            "Zoom should be 120 after two Shift+Up events"
        )

        app.typeKey("0", modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(100, in: zoomField),
            "Zoom should be 100 after pressing 0"
        )

        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNumericValue(110, in: zoomField))

        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(100, in: zoomField),
            "Zoom should be 100 after R"
        )
    }

    func testLockWorkflow() throws {
        XCTAssertTrue(isVideoLoaded())

        let zoomField = app.textFields["input-zoom"]
        let lockButton = app.buttons["button-lock"]

        ensureUnlocked()
        XCTAssertTrue(zoomField.isEnabled, "Zoom field enabled when unlocked")

        zoomField.click()
        app.typeKey(.upArrow, modifierFlags: .shift)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForNumericValue(110, in: zoomField),
            "Shift+Up should change zoom before locking"
        )

        lockButton.click()
        XCTAssertTrue(waitForValue("Locked", in: lockButton))
        XCTAssertTrue(
            waitForEnabled(false, element: zoomField),
            "Zoom field should be disabled while locked"
        )

        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(waitForValue("Unlocked", in: lockButton))
        XCTAssertTrue(
            waitForEnabled(true, element: zoomField),
            "Zoom field should be enabled after unlocking"
        )

        app.typeKey("r", modifierFlags: [])
    }
}
