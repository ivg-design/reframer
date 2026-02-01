import XCTest

final class ZoomScreenshotTest: XCTestCase {
    
    let screenshotDir = "/Users/ivg/github/video-overlay/Reframer/screenshots"
    
    func testZoomVisualVerification() throws {
        // Create screenshot directory
        try? FileManager.default.createDirectory(atPath: screenshotDir, withIntermediateDirectories: true)
        
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["TEST_VIDEO_PATH"] = "/Users/ivg/github/video-overlay/Reframer/ReframerTests/TestFixtures/test-video.mp4"
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
        let url1 = URL(fileURLWithPath: "\(screenshotDir)/zoom_100_percent.png")
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
        let url2 = URL(fileURLWithPath: "\(screenshotDir)/zoom_200_percent.png")
        try screen2.pngRepresentation.write(to: url2)
        
        app.terminate()
    }
}
