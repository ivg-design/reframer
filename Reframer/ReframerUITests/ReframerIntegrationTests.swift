import XCTest

/// Comprehensive integration tests with video loaded.
/// Each test launches with isolated preferences, opens its fixture through
/// Launch Services, and restores a known UI state.
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
        UITestConfig.configure(app)
        app.launch()
        XCTAssertTrue(
            UITestVideoLoader.openAndWaitForReady(fixtureURL, in: app),
            "Fixture should open through Launch Services"
        )
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

    private func hittableMenuItem(titled title: String) -> XCUIElement? {
        let matches = app.menuItems.matching(
            NSPredicate(format: "title == %@", title)
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                matches.allElementsBoundByIndex.contains(where: \.isHittable)
            },
            object: nil
        )
        guard XCTWaiter.wait(for: [expectation], timeout: 2) == .completed else {
            return nil
        }
        return matches.allElementsBoundByIndex.first(where: \.isHittable)
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

    private func valueRemains(
        _ expected: String,
        in element: XCUIElement,
        duration: TimeInterval = 0.5
    ) -> Bool {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", expected),
            object: element
        )
        changed.isInverted = true
        return XCTWaiter.wait(for: [changed], timeout: duration) == .completed
    }

    private func relaunchPreservingIsolatedPreferences() {
        app.terminate()
        UITestConfig.configure(app, resetPreferences: false)
        app.launch()
        XCTAssertTrue(
            UITestVideoLoader.openAndWaitForReady(fixtureURL, in: app),
            "Relaunch should reopen the fixture through Launch Services"
        )
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

    func testVideoAndControlsAreOneCanonicalManagedWindow() {
        let mainWindow = app.windows["window-main"]
        XCTAssertTrue(
            mainWindow.waitForExistence(timeout: 2),
            "The primary overlay window should exist"
        )
        XCTAssertTrue(
            mainWindow.buttons["button-open"].waitForExistence(timeout: 2),
            "Playback controls must be descendants of the primary overlay window"
        )
        XCTAssertTrue(
            mainWindow.textFields["input-frame"].exists,
            "Control fields must belong to the same managed window as the video"
        )
        XCTAssertFalse(
            app.windows["window-controls"].exists,
            "A separately targetable control window must never be exposed to window managers"
        )
    }

    func testReplacementOpenPanelRetainsNativeKeyboardInput() {
        let initialFrame = getFrameValue()
        let playButton = app.buttons["button-play"]
        XCTAssertTrue(waitForValue("Paused", in: playButton))

        app.typeKey("o", modifierFlags: .command)
        let openPanel = app.sheets.firstMatch
        XCTAssertTrue(
            openPanel.waitForExistence(timeout: 5),
            "Command-O should present a replacement file-picker sheet"
        )
        let cancelButton = openPanel.buttons["Cancel"].firstMatch
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 5),
            "Command-O should present the replacement file picker"
        )

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(" ", modifierFlags: [])
        XCTAssertEqual(
            getFrameValue(),
            initialFrame,
            "File-panel navigation must not pan or step the loaded video"
        )
        XCTAssertTrue(
            valueRemains("Paused", in: playButton),
            "Space in the file panel must not toggle playback"
        )

        // Space is a native Quick Look command in an open panel. Toggle it
        // back off before verifying the panel's native Escape dismissal.
        app.typeKey(" ", modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        if openPanel.exists {
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(
            waitForHittable(false, element: openPanel),
            "Escape should dismiss the replacement file picker"
        )
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

    func testLockButtonLocksAndLocalKeyboardUnlocksOverlay() throws {
        ensureUnlocked()

        let lockButton = app.buttons["button-lock"]
        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(lockButton.exists)

        lockButton.click()
        XCTAssertTrue(waitForValue("Locked", in: lockButton))
        XCTAssertTrue(
            waitForEnabled(false, element: zoomField),
            "Locking must disable overlay controls"
        )

        // XCUITest dispatches this key to the active app; this proves the local
        // recovery path, not cross-application Carbon delivery or WindowServer
        // click-through. Those behaviors require the separate live-system gate.
        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(waitForValue("Unlocked", in: lockButton))
        XCTAssertTrue(
            waitForEnabled(true, element: zoomField),
            "Local keyboard recovery must restore overlay controls"
        )
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

    /// The app-active path covers both directions and every advertised factor.
    func testFrameStepShortcutsCoverBothDirectionsAndMultipliers() throws {
        XCTAssertTrue(isVideoLoaded())
        let frameField = app.textFields["input-frame"]
        frameField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("20")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForNumericValue(20, in: frameField))

        app.typeKey(.pageDown, modifierFlags: .command)
        XCTAssertTrue(
            waitForNumericValue(21, in: frameField),
            "Command-Page Down should advance one frame"
        )

        app.typeKey(.pageDown, modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForNumericValue(31, in: frameField),
            "Command-Shift-Page Down should advance ten frames"
        )

        app.typeKey(.pageUp, modifierFlags: .command)
        XCTAssertTrue(
            waitForNumericValue(30, in: frameField),
            "Command-Page Up should reverse one frame"
        )

        app.typeKey(.pageUp, modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitForNumericValue(20, in: frameField),
            "Command-Shift-Page Up should reverse ten frames"
        )
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
        opacityField.click()
        app.typeKey(.upArrow, modifierFlags: .shift)
        XCTAssertTrue(
            waitForNumericValue(60, in: opacityField),
            "Shift+Up should increase opacity by 10 percentage points"
        )

        app.typeKey(.escape, modifierFlags: [])
    }

    func testQuickFilterParameterlessDisablesSlider() throws {
        XCTAssertTrue(isVideoLoaded())

        let filterButton = app.popUpButtons["button-filter-menu"]
        XCTAssertTrue(
            filterButton.waitForExistence(timeout: 5),
            "Filter pop-up should exist"
        )

        // Select Invert (parameterless)
        filterButton.click()
        guard let invertItem = hittableMenuItem(titled: "Invert") else {
            XCTFail("The quick-filter button should present the Invert menu item")
            return
        }
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
        guard let brightnessItem = hittableMenuItem(titled: "Brightness") else {
            XCTFail("The quick-filter button should present the Brightness menu item")
            return
        }
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

    func testFilterAndDocumentationShortcutsOpenAndEscapeCloses() {
        app.typeKey("f", modifierFlags: [])
        let filterWindow = app.windows["window-filter-panel"]
        XCTAssertTrue(
            filterWindow.waitForExistence(timeout: 3),
            "F should open Advanced Filters"
        )
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForHittable(false, element: filterWindow),
            "Escape should close Advanced Filters"
        )

        app.typeKey("/", modifierFlags: [.command, .shift])
        let documentationWindow = app.windows["window-documentation"]
        XCTAssertTrue(
            documentationWindow.waitForExistence(timeout: 3),
            "Command-? should open Reframer documentation"
        )
        let documentationContent = documentationWindow
            .descendants(matching: .any)["documentation-content"]
            .firstMatch
        XCTAssertTrue(
            documentationContent.waitForExistence(timeout: 3),
            "Documentation should expose its keyboard-scrollable content"
        )
        let documentationPage = documentationWindow
            .textViews["documentation-page"]
            .firstMatch
        XCTAssertTrue(
            documentationPage.waitForExistence(timeout: 3),
            "Documentation should render as native selectable text"
        )
        XCTAssertTrue(
            ((documentationPage.value as? String) ?? "").contains("Reframer Help"),
            "The Help window must contain rendered documentation, not an empty browser container"
        )
        XCTAssertTrue(
            ((documentationPage.value as? String) ?? "").contains("Product boundaries"),
            "The rendered page should include known bundled Help content"
        )
        documentationPage.click()
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(
            valueRemains("Paused", in: app.buttons["button-play"]),
            "Space in documentation must remain native scroll input"
        )
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForHittable(false, element: documentationWindow),
            "Escape should close documentation"
        )
    }

    func testEscapeClosesFrontmostPanelBeforeBackgroundPanel() {
        app.typeKey("h", modifierFlags: [])
        let shortcutSettings = app.groups["modal-help"]
        XCTAssertTrue(
            shortcutSettings.waitForExistence(timeout: 3),
            "H should open Shortcut Settings"
        )

        app.typeKey("f", modifierFlags: [])
        let filterWindow = app.windows["window-filter-panel"]
        XCTAssertTrue(
            filterWindow.waitForExistence(timeout: 3),
            "F should open Advanced Filters above Shortcut Settings"
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForHittable(false, element: filterWindow),
            "The first Escape should close the frontmost Advanced Filters panel"
        )
        XCTAssertTrue(
            shortcutSettings.isHittable,
            "Closing Advanced Filters must not close background Shortcut Settings"
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForHittable(false, element: shortcutSettings),
            "The second Escape should close Shortcut Settings"
        )
    }

    func testFocusedFilterControlsKeepNativeSpaceActivation() {
        let playButton = app.buttons["button-play"]
        XCTAssertTrue(waitForValue("Paused", in: playButton))

        let filterButton = app.popUpButtons["button-filter-menu"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.click()
        guard let invertItem = hittableMenuItem(titled: "Invert") else {
            XCTFail("Quick Filter should present Invert")
            return
        }
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(
            invertItem.waitForExistence(timeout: 2),
            "Space on the focused Quick Filter control should open its menu"
        )
        XCTAssertTrue(
            valueRemains("Paused", in: playButton),
            "Quick Filter activation must not also toggle playback"
        )
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("f", modifierFlags: [])
        let brightness = app.switches["Brightness"]
        XCTAssertTrue(brightness.waitForExistence(timeout: 3))
        brightness.click()
        let clickedValue = brightness.value as? String ?? ""
        app.typeKey(" ", modifierFlags: [])
        let toggled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", clickedValue),
            object: brightness
        )
        XCTAssertEqual(XCTWaiter.wait(for: [toggled], timeout: 3), .completed)
        XCTAssertTrue(
            valueRemains("Paused", in: playButton),
            "Space on a focused filter switch must not toggle playback"
        )
    }

    func testReboundShortcutReplacesOldChordAndPersistsDisable() {
        let playButton = app.buttons["button-play"]
        XCTAssertTrue(waitForValue("Paused", in: playButton))

        app.typeKey("h", modifierFlags: [])
        let shortcutButton = app.buttons["Play / Pause shortcut"]
        XCTAssertTrue(shortcutButton.waitForExistence(timeout: 3))
        shortcutButton.click()
        app.typeKey("j", modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(
            valueRemains("Paused", in: playButton),
            "The old Space binding should stop working after rebinding"
        )
        app.typeKey("j", modifierFlags: [])
        XCTAssertTrue(waitForValue("Playing", in: playButton))
        playButton.click()
        XCTAssertTrue(waitForValue("Paused", in: playButton))

        relaunchPreservingIsolatedPreferences()
        let relaunchedPlayButton = app.buttons["button-play"]
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(
            valueRemains("Paused", in: relaunchedPlayButton),
            "The replaced Space binding should remain inactive after relaunch"
        )
        app.typeKey("j", modifierFlags: [])
        XCTAssertTrue(waitForValue("Playing", in: relaunchedPlayButton))
        relaunchedPlayButton.click()
        XCTAssertTrue(waitForValue("Paused", in: relaunchedPlayButton))

        app.typeKey("h", modifierFlags: [])
        let enable = app.checkBoxes["Enable Play / Pause"]
        XCTAssertTrue(enable.waitForExistence(timeout: 3))
        enable.click()
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("j", modifierFlags: [])
        XCTAssertTrue(
            valueRemains("Paused", in: relaunchedPlayButton),
            "Disabling the rebound action should suppress it"
        )

        relaunchPreservingIsolatedPreferences()
        let disabledPlayButton = app.buttons["button-play"]
        app.typeKey("j", modifierFlags: [])
        XCTAssertTrue(
            valueRemains("Paused", in: disabledPlayButton),
            "Disabled shortcut state should survive relaunch"
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

        XCTAssertTrue(
            waitForNumericValue(initialVolume, in: volumeSlider, accuracy: 0.05),
            "Unmute should restore the previous volume"
        )
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
