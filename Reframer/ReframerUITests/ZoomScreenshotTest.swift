import XCTest

final class ZoomScreenshotTest: XCTestCase {

    private func fixtureURL(_ name: String, ext: String = "mp4") -> URL {
        let fileURL = URL(fileURLWithPath: #file)
        let baseURL = fileURL.deletingLastPathComponent().deletingLastPathComponent() // .../Reframer
        return baseURL.appendingPathComponent("ReframerTests/TestFixtures/\(name).\(ext)")
    }

    let screenshotDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ReframerScreenshots", isDirectory: true)
    
    func testZoomVisualVerification() throws {
        guard ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] == "1" else {
            throw XCTSkip("Set UITEST_SCREENSHOTS=1 to capture screenshots")
        }

        // Create screenshot directory
        try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
        
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["TEST_VIDEO_PATH"] = fixtureURL("test-video").path
        app.launch()
        
        // Wait for video to load
        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(zoomField.waitForExistence(timeout: 5), "Zoom field should exist")
        Thread.sleep(forTimeInterval: 1)
        
        // Verify initial zoom is 100%
        let zoom1 = zoomField.value as? String ?? "?"
        XCTAssertEqual(zoom1, "100", "Initial zoom should be 100%")
        
        // Screenshot at 100%
        let screen1 = XCUIScreen.main.screenshot()
        let url1 = screenshotDir.appendingPathComponent("zoom_100_percent.png")
        try screen1.pngRepresentation.write(to: url1)
        
        // Zoom to 200%
        zoomField.doubleTap()
        Thread.sleep(forTimeInterval: 0.2)
        app.typeText("200")
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        
        // Verify zoom is now 200%
        let zoom2 = zoomField.value as? String ?? "?"
        XCTAssertEqual(zoom2, "200", "Zoom should be 200% after typing")
        
        // Screenshot at 200%
        let screen2 = XCUIScreen.main.screenshot()
        let url2 = screenshotDir.appendingPathComponent("zoom_200_percent.png")
        try screen2.pngRepresentation.write(to: url2)
        
        app.terminate()
    }
}
