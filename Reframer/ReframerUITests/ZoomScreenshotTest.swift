import XCTest

final class ZoomScreenshotTest: XCTestCase {

    private let screenshotDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ReframerScreenshots", isDirectory: true)

    func testZoomFieldChangesFrom100To200Percent() throws {
        let fixture = UITestVideoLoader.fixtureURL(
            named: "test-video",
            relativeTo: #filePath
        )
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-VideoOverlay.quickFilter", "__UITEST_NONE__",
            "-VideoOverlay.opacity", "1.0"
        ]
        app.launch()

        addTeardownBlock {
            app.terminate()
        }

        XCTAssertTrue(
            UITestVideoLoader.open(fixture, in: app),
            "Fixture should open through Launch Services"
        )

        let zoomField = app.textFields["input-zoom"]
        XCTAssertTrue(
            zoomField.waitForExistence(timeout: 8),
            "A loaded fixture should expose the zoom field"
        )
        XCTAssertTrue(
            waitForZoom(100, in: zoomField),
            "Initial zoom should settle at 100%"
        )
        try captureIfRequested(named: "zoom_100_percent")

        zoomField.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("200")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitForZoom(200, in: zoomField),
            "Entering 200 should update the observable zoom value to 200%"
        )
        try captureIfRequested(named: "zoom_200_percent")
    }

    private func waitForZoom(
        _ expected: Double,
        in field: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            let value: Double?
            if let number = field.value as? NSNumber {
                value = number.doubleValue
            } else if let rawValue = field.value as? String {
                value = Double(rawValue.replacingOccurrences(of: "%", with: ""))
            } else {
                value = nil
            }
            guard let value else { return false }
            return abs(value - expected) < 0.05
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: field)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func captureIfRequested(named name: String) throws {
        guard ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] == "1" else {
            return
        }

        try FileManager.default.createDirectory(
            at: screenshotDirectory,
            withIntermediateDirectories: true
        )
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        try screenshot.pngRepresentation.write(
            to: screenshotDirectory.appendingPathComponent("\(name).png")
        )
    }
}
