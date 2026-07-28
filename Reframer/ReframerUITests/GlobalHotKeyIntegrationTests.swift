import XCTest

final class GlobalHotKeyIntegrationTests: XCTestCase {
    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ReframerTests/TestFixtures/test-video.mp4")
    }

    func testRegisteredHotKeysDispatchOnceAcrossApplications() throws {
        guard ProcessInfo.processInfo.environment["REFRAMER_UI_RUNNER_AUTHORIZED"] == "1"
        else {
            throw XCTSkip("Requires the authorized, logged-in self-hosted UI runner")
        }

        let reframer = XCUIApplication()
        reframer.launchEnvironment["UITEST_MODE"] = "1"
        reframer.launch()
        XCTAssertTrue(UITestVideoLoader.open(fixtureURL(), in: reframer))

        let timeline = reframer.sliders["slider-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 8))
        XCTAssertTrue(timeline.isEnabled)

        // Fail clearly if this machine already owns one of the defaults.
        reframer.typeKey("h", modifierFlags: [])
        let status = reframer.staticTexts["shortcut-validation-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 2))
        XCTAssertTrue(
            status.label.contains("5 global shortcuts registered"),
            "Expected every default registered hot key to be active, got: \(status.label)"
        )
        reframer.typeKey(.escape, modifierFlags: [])

        if !isLocked(in: reframer) {
            reframer.typeKey("l", modifierFlags: [])
        }
        XCTAssertTrue(waitForLockState("Locked", in: reframer))

        let initialFrame = frameValue(in: reframer)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 3))
        finder.typeKey(.pageDown, modifierFlags: .command)

        reframer.activate()
        XCTAssertTrue(
            waitForFrame(initialFrame + 1, in: reframer),
            "One global Command-Page Down press should advance exactly one frame"
        )
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(
            frameValue(in: reframer),
            initialFrame + 1,
            "The local monitor and registered-hot-key handler must not double-dispatch"
        )

        // The registered lock chord also works while inactive. Once unlocked,
        // the existing global step guard must reject another external press.
        finder.activate()
        finder.typeKey("l", modifierFlags: [.command, .shift])
        reframer.activate()
        XCTAssertTrue(waitForLockState("Unlocked", in: reframer))
        let unlockedFrame = frameValue(in: reframer)

        finder.activate()
        finder.typeKey(.pageDown, modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.4)
        reframer.activate()
        XCTAssertEqual(
            frameValue(in: reframer),
            unlockedFrame,
            "Global frame stepping must remain guarded while the overlay is unlocked"
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
}
