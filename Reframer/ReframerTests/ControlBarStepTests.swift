import XCTest
@testable import Reframer

final class ControlBarStepTests: XCTestCase {
    func testStepCommandRecognizesModifiedSelectors() {
        XCTAssertEqual(ControlBar.stepCommand(for: #selector(NSResponder.moveUp(_:))), .up)
        XCTAssertEqual(ControlBar.stepCommand(for: #selector(NSResponder.moveDown(_:))), .down)
        XCTAssertEqual(ControlBar.stepCommand(for: #selector(NSResponder.moveUpAndModifySelection(_:))), .up)
        XCTAssertEqual(ControlBar.stepCommand(for: #selector(NSResponder.moveDownAndModifySelection(_:))), .down)
        XCTAssertEqual(ControlBar.stepCommand(for: #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:))), .up)
        XCTAssertEqual(ControlBar.stepCommand(for: #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:))), .down)
    }
}
