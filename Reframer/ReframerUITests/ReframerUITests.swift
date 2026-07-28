import XCTest

/// Empty-state UI coverage. Each test launches a fresh process so modal and
/// focus state from one test cannot affect another.
final class ReframerUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        UITestConfig.configure(app)
        app.launch()

        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5),
            "A fresh launch should expose the empty-state open action"
        )
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    private var emptyState: XCUIElement {
        app.buttons["drop-zone"]
    }

    private func assertOpenPickerAppears(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let openPanel = app.sheets.firstMatch
        XCTAssertTrue(
            openPanel.waitForExistence(timeout: 5),
            "The open-video action should present a sheet",
            file: file,
            line: line
        )
        let cancelButton = openPanel.buttons["Cancel"].firstMatch
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 5),
            "The open-video action should present a cancellable file picker",
            file: file,
            line: line
        )
        XCTAssertTrue(
            openPanel.buttons["Open"].firstMatch.waitForExistence(timeout: 2),
            "The file picker should expose its Open action",
            file: file,
            line: line
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForDisappearance(openPanel),
            "Cancelling should dismiss the file picker",
            file: file,
            line: line
        )
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 2),
            "Cancelling should return to the empty state",
            file: file,
            line: line
        )
    }

    @discardableResult
    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForUnhittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "isHittable == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func testEmptyStateExposesAccessibleOpenAction() {
        XCTAssertEqual(emptyState.label, "Open video")
        XCTAssertTrue(emptyState.isEnabled)
        XCTAssertTrue(emptyState.isHittable)

        let openButton = app.buttons["button-open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 2))
        XCTAssertEqual(openButton.label, "Open video")
        XCTAssertTrue(openButton.isEnabled)

        XCTAssertFalse(app.buttons["button-play"].isEnabled)
        XCTAssertFalse(app.buttons["button-step-backward"].isEnabled)
        XCTAssertFalse(app.buttons["button-step-forward"].isEnabled)
        XCTAssertFalse(app.sliders["slider-timeline"].isEnabled)
    }

    func testEmptyStatePressOpensPickerAndCancelRestoresState() {
        emptyState.click()
        assertOpenPickerAppears()
    }

    func testCommandOOpensPickerAndCancelRestoresState() {
        app.typeKey("o", modifierFlags: .command)
        assertOpenPickerAppears()
    }

    func testHelpShortcutPresentsAccessibleSettingsAndCloseRestoresEmptyState() {
        app.typeKey("h", modifierFlags: [])

        let help = app.groups["modal-help"]
        XCTAssertTrue(
            help.waitForExistence(timeout: 3),
            "H should present Shortcut Settings"
        )
        XCTAssertEqual(help.label, "Shortcut Settings")

        let closeButton = app.buttons["help-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
        XCTAssertEqual(closeButton.label, "Close Shortcut Settings")
        XCTAssertTrue(closeButton.isEnabled)
        XCTAssertTrue(closeButton.isHittable)

        closeButton.click()
        XCTAssertTrue(waitForUnhittable(help))
        XCTAssertTrue(emptyState.waitForExistence(timeout: 2))
        XCTAssertTrue(emptyState.isHittable)
    }
}
