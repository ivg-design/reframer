import XCTest

final class ReframerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false  // Don't run for each configuration - just once
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()

        // Verify app launched successfully
        XCTAssertTrue(app.exists, "App should launch successfully")

        if ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] == "1" {
            // Take a screenshot for reference
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Launch Screen"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
