import XCTest

/// UI-driven tests for MPV installation and playback.
final class MPVIntegrationTests: XCTestCase {

    private static var app: XCUIApplication?
    private static var appLaunched = false

    private var mpvVideoPath: String? {
        UITestConfig.value(for: "UITEST_MPV_VIDEO_PATH")
    }

    private var cleanMPV: String? {
        UITestConfig.value(for: "UITEST_CLEAN_MPV")
    }

    var app: XCUIApplication {
        if Self.app == nil {
            Self.app = XCUIApplication()
        }
        return Self.app!
    }

    override func setUpWithError() throws {
        continueAfterFailure = true

        guard let mpvPath = mpvVideoPath, !mpvPath.isEmpty else {
            throw XCTSkip("Set UITEST_MPV_VIDEO_PATH to run MPV tests")
        }

        if !Self.appLaunched {
            app.launchEnvironment["UITEST_MODE"] = "1"
            app.launchEnvironment["TEST_VIDEO_PATH"] = mpvPath
            if let cleanMPV = cleanMPV {
                app.launchEnvironment["UITEST_CLEAN_MPV"] = cleanMPV
            }
            app.launch()
            Self.appLaunched = true
        } else {
            app.activate()
        }
    }

    override class func tearDown() {
        app?.terminate()
        app = nil
        appLaunched = false
        super.tearDown()
    }

    // MARK: - Helpers

    private func waitForTimelineEnabled(timeout: TimeInterval = 300) -> Bool {
        let slider = app.sliders["slider-timeline"]
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: slider)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func tryInstallIfPrompted(in app: XCUIApplication) {
        let installSheet = app.sheets.firstMatch
        if installSheet.waitForExistence(timeout: 5) {
            let installButton = installSheet.buttons["Install MPV"]
            if installButton.exists {
                installButton.click()
            }
        }
    }

    // MARK: - Tests

    /// Verify MPV install prompt appears (if needed) and playback starts for WebM.
    func testWebMPlayback_AfterMPVInstallIfNeeded() throws {
        tryInstallIfPrompted(in: app)

        XCTAssertTrue(waitForTimelineEnabled(), "Timeline should enable after MPV playback loads")

        // Sanity: zoom field exists and can be edited
        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(zoomField.waitForExistence(timeout: 5), "Zoom field should exist")
        zoomField.click()
        zoomField.typeKey("a", modifierFlags: .command)
        zoomField.typeText("150")
        app.typeKey(.return, modifierFlags: [])

        let zoomValue = (zoomField.value as? String) ?? ""
        XCTAssertTrue(zoomValue.contains("150"), "Zoom field should update to 150")
    }

    /// Verify MPV install route is available in Preferences.
    func testPreferencesInstallRoute() throws {
        app.typeKey(",", modifierFlags: .command)

        let prefsWindow = app.windows["Preferences"]
        XCTAssertTrue(prefsWindow.waitForExistence(timeout: 5), "Preferences window should appear")

        let installButton = prefsWindow.buttons["prefs-mpv-install"]
        let uninstallButton = prefsWindow.buttons["prefs-mpv-uninstall"]
        let enableCheckbox = prefsWindow.checkBoxes["prefs-mpv-enable"]

        if installButton.exists {
            installButton.click()
            XCTAssertTrue(uninstallButton.waitForExistence(timeout: 300), "Uninstall button should appear after install")
        } else {
            XCTAssertTrue(uninstallButton.exists, "Uninstall button should exist when MPV is installed")
        }

        if enableCheckbox.exists {
            enableCheckbox.click()
            enableCheckbox.click()
        }
    }

    /// Optional AV1 playback check (uses separate app launch).
    func testAV1PlaybackIfProvided() throws {
        guard let av1Path = UITestConfig.value(for: "UITEST_AV1_VIDEO_PATH"),
              !av1Path.isEmpty else {
            throw XCTSkip("Set UITEST_AV1_VIDEO_PATH to run AV1 playback test")
        }

        let av1App = XCUIApplication()
        av1App.launchEnvironment["UITEST_MODE"] = "1"
        av1App.launchEnvironment["TEST_VIDEO_PATH"] = av1Path
        if let cleanMPV = cleanMPV {
            av1App.launchEnvironment["UITEST_CLEAN_MPV"] = cleanMPV
        }
        av1App.launch()

        tryInstallIfPrompted(in: av1App)

        let slider = av1App.sliders["slider-timeline"]
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: slider)
        let result = XCTWaiter.wait(for: [expectation], timeout: 120)
        XCTAssertEqual(result, .completed, "Timeline should enable for AV1 playback")

        av1App.terminate()
    }
}
