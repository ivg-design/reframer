import XCTest

final class ReframerYouTubeUITests: XCTestCase {
    func testYouTubePlaybackIfConfigured() throws {
        guard let youtubeURL = ProcessInfo.processInfo.environment["UITEST_YOUTUBE_URL"],
              !youtubeURL.isEmpty else {
            throw XCTSkip("Set UITEST_YOUTUBE_URL to run this test")
        }

        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()

        let openButton = app.buttons["button-open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5), "Open button should exist")
        openButton.press(forDuration: 0.4)

        let inputField = app.textFields["youtube-url-input"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5), "YouTube URL input should appear")
        inputField.click()
        inputField.typeText(youtubeURL)

        if app.buttons["Open"].exists {
            app.buttons["Open"].click()
        }

        let slider = app.sliders["slider-timeline"]
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: slider)
        let result = XCTWaiter.wait(for: [expectation], timeout: 30)
        XCTAssertEqual(result, .completed, "Timeline should enable after YouTube video loads")
    }
}
