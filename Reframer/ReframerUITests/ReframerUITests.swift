import XCTest

final class ReframerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Basic Launch Tests

    func testAppLaunches() throws {
        // App should launch without crash - if we get here, it worked
        XCTAssertTrue(app.exists, "App should exist after launch")
    }

    func testWindowExists() throws {
        // Should have at least one window
        XCTAssertGreaterThanOrEqual(app.windows.count, 1, "Should have at least one window")
    }

    // MARK: - Keyboard Shortcut Tests

    func testEscapeDoesNotCrash() throws {
        // Press Escape - should not crash
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Escape")
    }

    func testSpacebarDoesNotCrash() throws {
        // Press Spacebar - should not crash (play/pause when no video)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Spacebar")
    }
}
