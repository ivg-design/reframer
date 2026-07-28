import XCTest

/// Verifies Carbon registration state transitions exposed by the app.
///
/// XCUITest's `typeKey` API targets an application directly, so this suite does
/// not claim to prove physical cross-application hot-key delivery.
final class GlobalHotKeyRegistrationIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCarbonRegistrationLifecycleAcrossApplicationState() throws {
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
            // Return intentionally ended text editing but left the field as
            // the focused control. Use the button here so this registration
            // test does not contradict the native text-input ownership rule.
            reframer.buttons["button-lock"].click()
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

        // XCUITest sends typeKey events directly to its target application;
        // it does not feed them back through WindowServer's Carbon hot-key
        // route. Exercise the real registration lifecycle here, and reserve
        // physical cross-app delivery for the documented live gate.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 3))
        XCTAssertTrue(
            reframer.wait(for: .runningBackground, timeout: 3),
            "Reframer should retain its registrations while inactive"
        )

        reframer.activate()
        // The locked overlay is deliberately pointer-transparent. XCUITest
        // sends this key to the active app, exercising local recovery without
        // pretending to traverse WindowServer's Carbon delivery path.
        reframer.typeKey("l", modifierFlags: [])
        XCTAssertTrue(waitForLockState("Unlocked", in: reframer))

        reframer.typeKey("h", modifierFlags: [])
        XCTAssertTrue(
            waitForRegistrationCount(1, in: reframer),
            "Only the globally available lock chord should remain registered"
        )
        reframer.typeKey(.escape, modifierFlags: [])

        reframer.buttons["button-lock"].click()
        XCTAssertTrue(waitForLockState("Locked", in: reframer))
        reframer.typeKey("h", modifierFlags: [])
        XCTAssertTrue(
            waitForRegistrationCount(5, in: reframer),
            "Relocking should restore all four frame registrations"
        )
        reframer.typeKey(.escape, modifierFlags: [])
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
