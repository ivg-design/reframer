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

    func testMixedDropSelectsTheSameFirstSupportedURLItValidates() {
        let unsupported = URL(fileURLWithPath: "/tmp/cover.png")
        let firstSupported = URL(fileURLWithPath: "/tmp/clip.mov")
        let secondSupported = URL(fileURLWithPath: "/tmp/clip.mp4")

        XCTAssertEqual(
            DropZoneView.firstSupportedVideoURL(
                in: [unsupported, firstSupported, secondSupported]
            ),
            firstSupported
        )
        XCTAssertNil(
            DropZoneView.firstSupportedVideoURL(
                in: [
                    unsupported,
                    URL(fileURLWithPath: "/tmp/notes.txt")
                ]
            )
        )
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
        XCTAssertEqual(
            menu.items.first(where: { $0.title == "Brightness" })?
                .accessibilityLabel(),
            "Quick filter: Brightness"
        )
        XCTAssertEqual(button.accessibilityRole(), .popUpButton)
        XCTAssertEqual(button.accessibilityValue() as? String, "None")
        XCTAssertEqual(button.isAccessibilityEnabled(), true)
    }
}

@MainActor
final class FilterPanelAccessibilityTests: XCTestCase {
    func testAdvancedFilterPanelHasNamedControlsAndDeterministicInitialFocus() {
        let state = VideoState()
        let panel = FilterPanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 500))
        panel.videoState = state

        let brightnessToggle = descendant(
            withIdentifier: "filter-toggle-brightness",
            in: panel
        ) as? NSSwitch
        let closeButton = descendant(
            withIdentifier: "filter-panel-close",
            in: panel
        ) as? NSButton

        XCTAssertEqual(panel.accessibilityRole(), .group)
        XCTAssertEqual(panel.accessibilityLabel(), "Advanced filters")
        XCTAssertTrue(panel.preferredInitialFirstResponder === brightnessToggle)
        XCTAssertEqual(brightnessToggle?.accessibilityLabel(), "Brightness")
        XCTAssertFalse(brightnessToggle?.accessibilityHelp()?.isEmpty ?? true)
        XCTAssertEqual(closeButton?.accessibilityLabel(), "Close advanced filters")
        XCTAssertFalse(closeButton?.accessibilityHelp()?.isEmpty ?? true)
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
