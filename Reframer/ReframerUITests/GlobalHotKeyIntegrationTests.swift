import XCTest

final class GlobalHotKeyIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRegisteredHotKeysDispatchOnceAcrossApplications() throws {
        guard ProcessInfo.processInfo.environment["REFRAMER_UI_RUNNER_AUTHORIZED"] == "1"
        else {
            XCTFail(
                "Run this target through scripts/runner_test.sh on the acknowledged UI runner"
            )
            return
        }

        let reframer = XCUIApplication()
        UITestConfig.configure(reframer)
        reframer.launch()
        addTeardownBlock {
            reframer.terminate()
        }

        let fixture = UITestVideoLoader.fixtureURL(
            named: "test-video",
            relativeTo: #filePath
        )
        XCTAssertTrue(UITestVideoLoader.openAndWaitForReady(fixture, in: reframer))

        let frameField = reframer.textFields["input-frame"]
        frameField.click()
        reframer.typeKey("a", modifierFlags: .command)
        reframer.typeText("20")
        reframer.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitForFrame(20, in: reframer),
            "The fixture should seek away from its clamp boundaries"
        )

        if !isLocked(in: reframer) {
            reframer.typeKey("l", modifierFlags: [])
        }
        XCTAssertTrue(waitForLockState("Locked", in: reframer))

        // Fail clearly if this machine already owns one of the defaults. The
        // four frame variants are registered only in their actionable state.
        reframer.typeKey("h", modifierFlags: [])
        XCTAssertTrue(
            waitForRegistrationCount(5, in: reframer),
            "All actionable defaults should register without a conflict"
        )
        reframer.typeKey(.escape, modifierFlags: [])

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        assertGlobalStep(
            key: .pageDown,
            modifiers: .command,
            expectedFrame: 21,
            finder: finder,
            reframer: reframer,
            message: "Command-Page Down should advance exactly one frame"
        )
        assertGlobalStep(
            key: .pageDown,
            modifiers: [.command, .shift],
            expectedFrame: 31,
            finder: finder,
            reframer: reframer,
            message: "Command-Shift-Page Down should advance exactly ten frames"
        )
        assertGlobalStep(
            key: .pageUp,
            modifiers: .command,
            expectedFrame: 30,
            finder: finder,
            reframer: reframer,
            message: "Command-Page Up should reverse exactly one frame"
        )
        assertGlobalStep(
            key: .pageUp,
            modifiers: [.command, .shift],
            expectedFrame: 20,
            finder: finder,
            reframer: reframer,
            message: "Command-Shift-Page Up should reverse exactly ten frames"
        )

        // The lock chord stays registered in every state. Unlocking removes
        // the exclusive frame registrations, so other apps keep those keys.
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 3))
        finder.typeKey("l", modifierFlags: [.command, .shift])
        reframer.activate()
        XCTAssertTrue(waitForLockState("Unlocked", in: reframer))
        let unlockedFrame = frameValue(in: reframer)

        reframer.typeKey("h", modifierFlags: [])
        XCTAssertTrue(
            waitForRegistrationCount(1, in: reframer),
            "Only the globally available lock chord should remain registered"
        )
        reframer.typeKey(.escape, modifierFlags: [])

        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 3))
        finder.typeKey(.pageDown, modifierFlags: .command)
        XCTAssertTrue(
            frameRemains(unlockedFrame, in: reframer),
            "An unlocked overlay must not receive or swallow global frame steps"
        )
    }

    private func assertGlobalStep(
        key: XCUIKeyboardKey,
        modifiers: XCUIElement.KeyModifierFlags,
        expectedFrame: Int,
        finder: XCUIApplication,
        reframer: XCUIApplication,
        message: String
    ) {
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 3))
        finder.typeKey(key, modifierFlags: modifiers)
        reframer.activate()
        XCTAssertTrue(waitForFrame(expectedFrame, in: reframer), message)
        XCTAssertTrue(
            frameRemains(expectedFrame, in: reframer),
            "\(message); the event must not dispatch twice"
        )
    }

    private func frameValue(in app: XCUIApplication) -> Int {
        Int(app.textFields["input-frame"].value as? String ?? "") ?? -1
    }

    private func isLocked(in app: XCUIApplication) -> Bool {
        app.buttons["button-lock"].value as? String == "Locked"
    }

    private func waitForFrame(
        _ expected: Int,
        in app: XCUIApplication,
        timeout: TimeInterval = 3
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.frameValue(in: app) == expected },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func frameRemains(
        _ expected: Int,
        in app: XCUIApplication,
        duration: TimeInterval = 0.5
    ) -> Bool {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.frameValue(in: app) != expected },
            object: nil
        )
        changed.isInverted = true
        return XCTWaiter.wait(for: [changed], timeout: duration) == .completed
    }

    private func waitForLockState(
        _ expected: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3
    ) -> Bool {
        let button = app.buttons["button-lock"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: button
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForRegistrationCount(
        _ count: Int,
        in app: XCUIApplication,
        timeout: TimeInterval = 4
    ) -> Bool {
        let status = app.staticTexts["shortcut-validation-status"]
        let text = "\(count) global shortcut\(count == 1 ? "" : "s") registered"
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text),
            object: status
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
