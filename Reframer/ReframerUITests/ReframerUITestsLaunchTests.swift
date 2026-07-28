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
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-VideoOverlay.quickFilter", "__UITEST_NONE__"
        ]
        app.launch()
        addTeardownBlock {
            app.terminate()
        }

        let openAction = app.buttons["drop-zone"]
        XCTAssertTrue(
            openAction.waitForExistence(timeout: 5),
            "Launch should reach the actionable empty state"
        )
        XCTAssertEqual(openAction.label, "Open video")
        XCTAssertTrue(openAction.isEnabled)

        if ProcessInfo.processInfo.environment["UITEST_SCREENSHOTS"] == "1" {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Empty State"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
