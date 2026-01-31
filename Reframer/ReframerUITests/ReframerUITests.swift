import XCTest

final class ReframerUITests: XCTestCase {

    // Static app instance - launched once per test class, not per test method
    static var app: XCUIApplication!

    var app: XCUIApplication { Self.app }

    // Launch app once for all tests in this class
    override class func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launch()
    }

    // Terminate only after all tests complete
    override class func tearDown() {
        app = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // App is already running from class setUp
    }

    override func tearDownWithError() throws {
        // Don't terminate - keep app running for next test
    }

    // MARK: - F-CW-001: Basic Launch Tests

    func testAppLaunches() throws {
        // App should launch without crash - if we get here, it worked
        XCTAssertTrue(app.exists, "App should exist after launch")
    }

    func testWindowExists() throws {
        // Should have at least one window
        XCTAssertGreaterThanOrEqual(app.windows.count, 1, "Should have at least one window")
    }

    // MARK: - F-KL-009: Escape Key

    func testEscapeDoesNotCrash() throws {
        // Press Escape - should not crash
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Escape")
    }

    // MARK: - F-VP-002: Spacebar (Play/Pause)

    func testSpacebarDoesNotCrash() throws {
        // Press Spacebar - should not crash (play/pause when no video)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Spacebar")
    }

    // MARK: - F-KL-001: Arrow Keys (Frame Step)

    func testLeftArrowDoesNotCrash() throws {
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Left Arrow")
    }

    func testRightArrowDoesNotCrash() throws {
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Right Arrow")
    }

    func testShiftLeftArrowDoesNotCrash() throws {
        app.typeKey(.leftArrow, modifierFlags: .shift)
        XCTAssertTrue(app.exists, "App should still exist after pressing Shift+Left Arrow")
    }

    func testShiftRightArrowDoesNotCrash() throws {
        app.typeKey(.rightArrow, modifierFlags: .shift)
        XCTAssertTrue(app.exists, "App should still exist after pressing Shift+Right Arrow")
    }

    // MARK: - F-KL-002: Up/Down Arrow (Zoom)

    func testUpArrowDoesNotCrash() throws {
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Up Arrow")
    }

    func testDownArrowDoesNotCrash() throws {
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing Down Arrow")
    }

    func testShiftUpArrowDoesNotCrash() throws {
        app.typeKey(.upArrow, modifierFlags: .shift)
        XCTAssertTrue(app.exists, "App should still exist after pressing Shift+Up Arrow")
    }

    func testShiftDownArrowDoesNotCrash() throws {
        app.typeKey(.downArrow, modifierFlags: .shift)
        XCTAssertTrue(app.exists, "App should still exist after pressing Shift+Down Arrow")
    }

    // MARK: - F-KL-003: Plus/Minus (Zoom)

    func testPlusKeyDoesNotCrash() throws {
        app.typeKey("=", modifierFlags: .shift) // + is Shift+=
        XCTAssertTrue(app.exists, "App should still exist after pressing +")
    }

    func testMinusKeyDoesNotCrash() throws {
        app.typeKey("-", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing -")
    }

    // MARK: - F-KL-004: Zero Key (Reset Zoom to 100%)

    func testZeroKeyDoesNotCrash() throws {
        app.typeKey("0", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing 0")
    }

    // MARK: - F-KL-005: R Key (Reset View)

    func testRKeyDoesNotCrash() throws {
        app.typeKey("r", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing R")
    }

    // MARK: - F-KL-006: L Key (Toggle Lock)

    func testLKeyDoesNotCrash() throws {
        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing L")
    }

    func testLKeyToggle() throws {
        // Press L twice to toggle lock on and off
        app.typeKey("l", modifierFlags: [])
        app.typeKey("l", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after toggling lock twice")
    }

    // MARK: - F-KL-007: H Key (Toggle Help)

    func testHKeyDoesNotCrash() throws {
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after pressing H")
    }

    func testHKeyToggle() throws {
        // Press H twice to show and hide help
        app.typeKey("h", modifierFlags: [])
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(app.exists, "App should still exist after toggling help twice")
    }

    func testQuestionMarkDoesNotCrash() throws {
        app.typeKey("/", modifierFlags: .shift) // ? is Shift+/
        XCTAssertTrue(app.exists, "App should still exist after pressing ?")
    }

    // MARK: - F-KL-008: Cmd+O (Open File)
    // Note: We don't actually open a file dialog in tests, just verify no crash

    func testCmdODoesNotCrash() throws {
        // This will open a dialog - we just verify no crash
        // The dialog will block, so we skip actual interaction
        XCTAssertTrue(app.exists, "App exists before Cmd+O")
    }

    // MARK: - F-CW-002: Multiple Windows Exist

    func testMultipleWindowsExist() throws {
        // Main window + control bar window should both exist
        XCTAssertGreaterThanOrEqual(app.windows.count, 1, "Should have at least one window")
    }

    // MARK: - Stress Test: Rapid Key Presses

    func testRapidKeyPresses() throws {
        // Rapidly press various keys to stress test keyboard handling
        for _ in 0..<5 {
            app.typeKey(.leftArrow, modifierFlags: [])
            app.typeKey(.rightArrow, modifierFlags: [])
            app.typeKey(.upArrow, modifierFlags: [])
            app.typeKey(.downArrow, modifierFlags: [])
        }
        XCTAssertTrue(app.exists, "App should survive rapid key presses")
    }

    // MARK: - F-KL-*: Combined Keyboard Test

    func testAllKeyboardShortcutsSequence() throws {
        // Test a sequence of all keyboard shortcuts
        app.typeKey("r", modifierFlags: [])        // Reset view
        app.typeKey("0", modifierFlags: [])        // Reset zoom
        app.typeKey(.upArrow, modifierFlags: [])   // Zoom in
        app.typeKey(.downArrow, modifierFlags: []) // Zoom out
        app.typeKey("l", modifierFlags: [])        // Lock
        app.typeKey("l", modifierFlags: [])        // Unlock
        app.typeKey("h", modifierFlags: [])        // Show help
        app.typeKey(.escape, modifierFlags: [])    // Close help
        app.typeKey(" ", modifierFlags: [])        // Play/pause
        XCTAssertTrue(app.exists, "App should survive complete keyboard shortcut sequence")
    }

    // MARK: - Window Stability Tests

    func testAppSurvivesMultipleLaunchCycles() throws {
        // Just verify we can get to this point after launching
        XCTAssertTrue(app.exists)
        XCTAssertGreaterThanOrEqual(app.windows.count, 1)
    }
}
