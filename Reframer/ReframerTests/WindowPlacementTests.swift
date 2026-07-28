import XCTest
@testable import Reframer

final class WindowPlacementTests: XCTestCase {
    private let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondary = NSRect(x: 1440, y: 100, width: 1200, height: 800)

    func testBestVisibleFrameUsesLargestIntersection() {
        let frame = NSRect(x: 1300, y: 200, width: 600, height: 500)

        XCTAssertEqual(
            WindowPlacement.bestVisibleFrame(
                for: frame,
                among: [primary, secondary]
            ),
            secondary
        )
    }

    func testBestVisibleFrameRecoversRemovedDisplayToNearestScreen() {
        let missingDisplayFrame = NSRect(x: 2800, y: 300, width: 500, height: 400)

        XCTAssertEqual(
            WindowPlacement.bestVisibleFrame(
                for: missingDisplayFrame,
                among: [primary, secondary]
            ),
            secondary
        )
    }

    func testMainFrameReservesVisibleToolbarSpace() {
        let offscreen = NSRect(x: -100, y: -20, width: 800, height: 560)
        let result = WindowPlacement.clampMainFrame(
            offscreen,
            visibleFrames: [primary],
            toolbarHeight: 80,
            minimumSize: NSSize(width: 640, height: 360)
        )

        XCTAssertGreaterThanOrEqual(result.minX, primary.minX)
        XCTAssertGreaterThanOrEqual(result.minY - 80, primary.minY)
        XCTAssertLessThanOrEqual(result.maxX, primary.maxX)
        XCTAssertLessThanOrEqual(result.maxY, primary.maxY)
    }

    func testOversizedMainFrameShrinksToAvailableArea() {
        let oversized = NSRect(x: -500, y: -500, width: 3000, height: 2000)
        let result = WindowPlacement.clampMainFrame(
            oversized,
            visibleFrames: [primary],
            toolbarHeight: 80,
            minimumSize: NSSize(width: 640, height: 360)
        )

        XCTAssertEqual(result.width, primary.width)
        XCTAssertEqual(result.height, primary.height - 80)
        XCTAssertEqual(result.minX, primary.minX)
        XCTAssertEqual(result.minY, primary.minY + 80)
    }

    func testAttachedPanelPrefersRightSide() {
        let anchor = NSRect(x: 200, y: 200, width: 600, height: 400)
        let result = WindowPlacement.attachedPanelFrame(
            size: NSSize(width: 320, height: 500),
            anchorFrame: anchor,
            visibleFrames: [primary]
        )

        XCTAssertEqual(result.minX, anchor.maxX + WindowPlacement.panelGap)
        XCTAssertTrue(primary.contains(result))
    }

    func testAttachedPanelFallsBackToLeftSide() {
        let anchor = NSRect(x: 900, y: 200, width: 500, height: 400)
        let result = WindowPlacement.attachedPanelFrame(
            size: NSSize(width: 320, height: 500),
            anchorFrame: anchor,
            visibleFrames: [primary]
        )

        XCTAssertEqual(
            result.minX,
            anchor.minX - WindowPlacement.panelGap - result.width
        )
        XCTAssertTrue(primary.contains(result))
    }

    func testAuxiliaryFrameIsFullyClamped() {
        let offscreen = NSRect(x: 2500, y: 850, width: 700, height: 600)
        let result = WindowPlacement.clampAuxiliaryFrame(
            offscreen,
            visibleFrames: [primary, secondary]
        )

        XCTAssertTrue(secondary.contains(result))
    }

    func testNonFiniteSavedMainFrameRecoversToUsableGeometry() {
        let invalid = NSRect(
            x: CGFloat.nan,
            y: CGFloat.infinity,
            width: -CGFloat.infinity,
            height: 0
        )

        let result = WindowPlacement.clampMainFrame(
            invalid,
            visibleFrames: [primary],
            toolbarHeight: 48,
            minimumSize: NSSize(width: 640, height: 360)
        )

        XCTAssertTrue(WindowPlacement.isUsableFrame(result))
        XCTAssertTrue(primary.contains(result))
        XCTAssertGreaterThanOrEqual(result.minY - 48, primary.minY)
    }

    func testInvalidVisibleFramesAreIgnored() {
        let invalidScreen = NSRect(
            x: CGFloat.nan,
            y: 0,
            width: 1920,
            height: 1080
        )
        let frame = NSRect(x: 1500, y: 200, width: 500, height: 400)

        XCTAssertEqual(
            WindowPlacement.bestVisibleFrame(
                for: frame,
                among: [invalidScreen, primary, secondary]
            ),
            secondary
        )
    }

    func testAttachedPanelWithNonFiniteInputStillFitsVisibleScreen() {
        let result = WindowPlacement.attachedPanelFrame(
            size: NSSize(width: CGFloat.infinity, height: CGFloat.nan),
            anchorFrame: NSRect(x: CGFloat.nan, y: 0, width: 0, height: 0),
            visibleFrames: [primary]
        )

        XCTAssertTrue(WindowPlacement.isUsableFrame(result))
        XCTAssertTrue(primary.contains(result))
    }
}
