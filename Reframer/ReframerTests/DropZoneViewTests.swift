import XCTest
@testable import Reframer

@MainActor
final class DropZoneViewTests: XCTestCase {
    func testLoadVideoAcceptsSupportedExtension() {
        let state = VideoState()
        let view = DropZoneView(frame: .zero)
        view.videoState = state

        let url = URL(fileURLWithPath: "/tmp/sample.mp4")
        let success = view.loadVideo(from: url)

        XCTAssertTrue(success)
        XCTAssertEqual(state.videoURL, url)
        XCTAssertFalse(state.isVideoLoaded, "Load should defer until player is ready")
    }

    func testLoadVideoRejectsUnsupportedExtension() {
        let state = VideoState()
        let view = DropZoneView(frame: .zero)
        view.videoState = state

        let url = URL(fileURLWithPath: "/tmp/sample.png")
        let success = view.loadVideo(from: url)

        XCTAssertFalse(success)
        XCTAssertNil(state.videoURL)
    }

    func testDropZoneIsKeyboardAndAccessibilityActionable() {
        let view = DropZoneView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let notification = expectation(forNotification: .openVideo, object: nil)

        XCTAssertTrue(view.acceptsFirstResponder)
        XCTAssertEqual(view.accessibilityRole(), .button)
        XCTAssertEqual(view.accessibilityLabel(), "Open video")
        XCTAssertTrue(view.accessibilityPerformPress())

        wait(for: [notification], timeout: 1)
    }

    func testEdgeIndicatorDoesNotBlockDropZoneHitTesting() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let dropZone = DropZoneView(frame: container.bounds)
        let edgeIndicator = EdgeIndicatorView(frame: container.bounds)
        container.addSubview(dropZone)
        container.addSubview(edgeIndicator)

        let center = NSPoint(x: container.bounds.midX, y: container.bounds.midY)
        XCTAssertNil(edgeIndicator.hitTest(center))
        XCTAssertTrue(container.hitTest(center) === dropZone)
    }
}

@MainActor
final class FilterMenuButtonTests: XCTestCase {
    func testPrimaryMenuExposesAllQuickFiltersAndAdvancedFilters() {
        let state = VideoState()
        let button = FilterMenuButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        button.videoState = state

        let menu = button.makeFilterMenu()
        let filterItems = menu.items.compactMap { $0.representedObject as? VideoFilter }

        XCTAssertEqual(filterItems, VideoFilter.simpleFilters)
        XCTAssertNotNil(menu.items.first(where: { $0.title == "None" }))
        XCTAssertNotNil(menu.items.first(where: { $0.title == "Advanced Filters..." }))
        XCTAssertEqual(button.accessibilityRole(), .popUpButton)
        XCTAssertEqual(button.accessibilityValue() as? String, "None")
    }
}
