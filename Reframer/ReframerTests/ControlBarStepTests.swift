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

final class VideoPointerPanSessionTests: XCTestCase {
    func testPointerPanPreservesStartingOffsetAndAppliesDragDelta() {
        let session = VideoPointerPanSession(
            startLocation: NSPoint(x: 120, y: 80),
            startOffset: CGSize(width: -14, height: 9)
        )

        XCTAssertEqual(
            session.offset(at: NSPoint(x: 153.5, y: 61)),
            CGSize(width: 19.5, height: -10)
        )
    }

    func testPointerPanCanReverseAcrossItsStartPoint() {
        let session = VideoPointerPanSession(
            startLocation: NSPoint(x: 50, y: 50),
            startOffset: CGSize(width: 4, height: -8)
        )

        XCTAssertEqual(
            session.offset(at: NSPoint(x: 40, y: 75)),
            CGSize(width: -6, height: 17)
        )
    }
}

@MainActor
final class OverlayInteractionContractTests: XCTestCase {
    func testWindowDragHandleExposesLockAwareAccessibilityState() {
        let handle = WindowDragHandle(
            frame: NSRect(x: 0, y: 0, width: 24, height: 32)
        )

        XCTAssertEqual(handle.identifier?.rawValue, "window-drag-handle")
        XCTAssertEqual(handle.accessibilityIdentifier(), "window-drag-handle")
        XCTAssertEqual(handle.accessibilityRole(), .handle)
        XCTAssertEqual(handle.accessibilityLabel(), "Move overlay window")
        XCTAssertEqual(handle.accessibilityValue() as? String, "Available")
        XCTAssertTrue(handle.isDragEnabled)

        handle.isDragEnabled = false

        XCTAssertEqual(
            handle.accessibilityValue() as? String,
            "Disabled while locked"
        )
        XCTAssertEqual(handle.toolTip, "Unlock the overlay before moving it")
    }

    func testReadyStatusSnapshotFormatsAndSanitizesValues() {
        let locked = ReadyStatusOverlaySnapshot(
            currentFrame: 42,
            totalFrames: 120,
            zoomScale: 1.251,
            isLocked: true
        )
        XCTAssertEqual(locked.frameText, "Frame 42 / 120")
        XCTAssertEqual(locked.zoomText, "Zoom 125.1%")
        XCTAssertEqual(locked.lockText, "Locked")
        XCTAssertTrue(locked.isLocked)

        let invalid = ReadyStatusOverlaySnapshot(
            currentFrame: -2,
            totalFrames: -10,
            zoomScale: .infinity,
            isLocked: false
        )
        XCTAssertEqual(invalid.frameText, "Frame 0 / 0")
        XCTAssertEqual(invalid.zoomText, "Zoom 100%")
        XCTAssertEqual(invalid.lockText, "Unlocked")
    }

    func testReadyStatusOverlayNeverInterceptsPointerInput() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let video = NSView(frame: container.bounds)
        let overlay = ReadyStatusOverlayView(
            frame: NSRect(x: 12, y: 250, width: 260, height: 28)
        )
        container.addSubview(video)
        container.addSubview(overlay)
        overlay.update(
            ReadyStatusOverlaySnapshot(
                currentFrame: 7,
                totalFrames: 90,
                zoomScale: 2,
                isLocked: true
            )
        )

        XCTAssertNil(overlay.hitTest(NSPoint(x: 20, y: 10)))
        XCTAssertTrue(container.hitTest(NSPoint(x: 20, y: 260)) === video)
        XCTAssertEqual(
            descendant(withIdentifier: "status-frame", in: overlay)?
                .accessibilityValue() as? String,
            "Frame 7 / 90"
        )
        XCTAssertEqual(
            descendant(withIdentifier: "status-zoom", in: overlay)?
                .accessibilityValue() as? String,
            "Zoom 200%"
        )
        XCTAssertEqual(
            descendant(withIdentifier: "status-lock", in: overlay)?
                .accessibilityValue() as? String,
            "Locked"
        )
    }

    private func descendant(
        withIdentifier identifier: String,
        in view: NSView
    ) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let match = descendant(withIdentifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
