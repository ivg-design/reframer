import XCTest

final class ReframerYouTubeUITests: XCTestCase {
    func testYouTubePlaybackIfConfigured() throws {
        guard let youtubeURL = UITestConfig.value(for: "UITEST_YOUTUBE_URL"),
              !youtubeURL.isEmpty else {
            throw XCTSkip("Set UITEST_YOUTUBE_URL to run this test")
        }

        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        if let cleanMPV = UITestConfig.value(for: "UITEST_CLEAN_MPV_YT") {
            app.launchEnvironment["UITEST_CLEAN_MPV"] = cleanMPV
        }
        app.launch()

        let openButton = app.buttons["button-open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), "Open button should exist")
        openButton.press(forDuration: 0.4)

        let inputField = app.textFields["youtube-url-input"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5), "YouTube URL input should appear")
        inputField.click()
        inputField.typeText(youtubeURL)

        let sheetOpen = app.sheets.buttons["Open"].firstMatch
        if sheetOpen.exists {
            sheetOpen.click()
        } else if app.buttons["Open"].firstMatch.exists {
            app.buttons["Open"].firstMatch.click()
        }

        // If MPV is required, install prompt may appear
        let installSheet = app.sheets.firstMatch
        if installSheet.waitForExistence(timeout: 8) {
            let installButton = installSheet.buttons["Install MPV"]
            if installButton.exists {
                installButton.click()
            }
        }

        let slider = app.sliders["slider-timeline"]
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: slider)
        let result = XCTWaiter.wait(for: [expectation], timeout: 90)
        XCTAssertEqual(result, .completed, "Timeline should enable after YouTube video loads")

        // Sanity check: zoom field should respond during MPV playback
        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(zoomField.waitForExistence(timeout: 5), "Zoom field should exist")
        zoomField.click()
        zoomField.typeKey("a", modifierFlags: .command)
        zoomField.typeText("110")
        app.typeKey(.return, modifierFlags: [])
    }
}
