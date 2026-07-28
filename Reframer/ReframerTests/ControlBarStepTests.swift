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

final class AccessibilityErrorAnnouncementTrackerTests: XCTestCase {
    func testTrackerAnnouncesOnlyNewNonEmptyErrorsAndResetsAfterClear() {
        var tracker = AccessibilityErrorAnnouncementTracker()

        XCTAssertNil(tracker.newMessageToAnnounce(nil))
        XCTAssertEqual(
            tracker.newMessageToAnnounce("  Filter failed.  "),
            "Filter failed."
        )
        XCTAssertNil(tracker.newMessageToAnnounce("Filter failed."))
        XCTAssertEqual(
            tracker.newMessageToAnnounce("A different error."),
            "A different error."
        )
        XCTAssertNil(tracker.newMessageToAnnounce(" \n "))
        XCTAssertEqual(
            tracker.newMessageToAnnounce("A different error."),
            "A different error."
        )
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
    func testWindowDragHandleKeyboardMovementRequiresOptionAndSupportsCoarseSteps() {
        XCTAssertEqual(
            WindowDragHandle.keyboardMoveDelta(
                keyCode: KeyCode.leftArrow,
                modifiers: [.option]
            ),
            CGSize(width: -1, height: 0)
        )
        XCTAssertEqual(
            WindowDragHandle.keyboardMoveDelta(
                keyCode: KeyCode.upArrow,
                modifiers: [.option, .shift]
            ),
            CGSize(width: 0, height: 10)
        )
        XCTAssertNil(
            WindowDragHandle.keyboardMoveDelta(
                keyCode: KeyCode.rightArrow,
                modifiers: []
            )
        )
        XCTAssertNil(
            WindowDragHandle.keyboardMoveDelta(
                keyCode: KeyCode.rightArrow,
                modifiers: [.option, .command]
            )
        )
    }

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
        XCTAssertEqual(
            handle.toolTip,
            "Locked above application windows with whole-overlay pointer pass-through; " +
                "move and resize are disabled. Use the configured global " +
                "Lock/Unlock shortcut to recover."
        )
        XCTAssertEqual(handle.accessibilityHelp(), handle.toolTip)
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
            descendant(withIdentifier: "status-frame", in: overlay)?
                .accessibilityRole(),
            .staticText
        )
        XCTAssertEqual(
            descendant(withIdentifier: "status-frame", in: overlay)?
                .isAccessibilityElement(),
            true
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

@MainActor
final class ControlBarLayoutRegressionTests: XCTestCase {
    private var retainedStates: [VideoState] = []

    func testResponsiveLayoutContractUsesRegularAndCompactHeights() {
        XCTAssertEqual(ControlBar.preferredFullWidth, 1_060)
        XCTAssertEqual(ControlBar.minimumWindowWidth, 640)
        XCTAssertEqual(ControlBar.compactLayoutBreakpoint, 920)
        XCTAssertEqual(
            ControlBar.layoutMode(for: 920),
            .regular
        )
        XCTAssertEqual(
            ControlBar.preferredHeight(for: 920),
            ControlBar.regularHeight
        )
        XCTAssertEqual(
            ControlBar.layoutMode(for: 919.5),
            .compact
        )
        XCTAssertEqual(
            ControlBar.preferredHeight(for: 919.5),
            ControlBar.compactHeight
        )
    }

    func testRegularPreferredWidthContainsEveryControlWithVolumeVisible() {
        assertEveryControlFits(
            width: ControlBar.preferredFullWidth,
            expectedHeight: ControlBar.regularHeight,
            expectedMode: .regular
        )
    }

    func testCompactMinimumWidthContainsEveryControlInTheExpectedRow() {
        let controlBar = makeWorstCaseControlBar(
            width: ControlBar.minimumWindowWidth,
            height: ControlBar.compactHeight
        )

        XCTAssertEqual(controlBar.layoutMode, .compact)
        assertEveryControlIsInside(controlBar)

        let primaryIdentifiers = [
            "window-drag-handle",
            "btn-open",
            "btn-step-back",
            "btn-play",
            "btn-step-forward",
            "slider-timeline",
            "btn-lock"
        ]
        let secondaryIdentifiers = [
            "field-frame",
            "label-frame-total",
            "field-zoom",
            "slider-opacity",
            "field-opacity",
            "btn-mute",
            "slider-volume",
            "btn-reset"
        ]

        for identifier in primaryIdentifiers {
            let row = ancestorStackIdentifier(
                of: descendant(withIdentifier: identifier, in: controlBar)
            )
            XCTAssertEqual(
                row,
                "primary-control-row",
                "\(identifier) must remain in the compact primary row"
            )
        }
        for identifier in secondaryIdentifiers {
            let row = ancestorStackIdentifier(
                of: descendant(withIdentifier: identifier, in: controlBar)
            )
            XCTAssertEqual(
                row,
                "secondary-control-row",
                "\(identifier) must remain in the compact secondary row"
            )
        }

        let primaryRow = descendant(
            withIdentifier: "primary-control-row",
            in: controlBar
        )
        let secondaryRow = descendant(
            withIdentifier: "secondary-control-row",
            in: controlBar
        )
        XCTAssertEqual(primaryRow?.bounds.height, ControlBar.regularHeight)
        XCTAssertEqual(secondaryRow?.bounds.height, ControlBar.regularHeight)

        assertControlsDoNotOverlap(in: controlBar)
        assertLongFrameMetadataFits(in: controlBar)
    }

    func testPreferredHeightCallbackReportsModeTransition() {
        let controlBar = ControlBar(
            frame: NSRect(
                x: 0,
                y: 0,
                width: ControlBar.preferredFullWidth,
                height: ControlBar.regularHeight
            )
        )
        var reportedHeights: [CGFloat] = []
        controlBar.onPreferredHeightChange = { reportedHeights.append($0) }

        controlBar.setFrameSize(
            NSSize(
                width: ControlBar.minimumWindowWidth,
                height: ControlBar.compactHeight
            )
        )
        controlBar.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            reportedHeights,
            [ControlBar.regularHeight, ControlBar.compactHeight]
        )
    }

    func testLockButtonRequestsOneCentrallyGuardedToggle() {
        let controlBar = makeWorstCaseControlBar(
            width: ControlBar.preferredFullWidth,
            height: ControlBar.regularHeight
        )
        guard let lockButton = descendant(
            withIdentifier: "btn-lock",
            in: controlBar
        ) as? NSButton else {
            return XCTFail("Missing lock button")
        }

        var requestCount = 0
        controlBar.onToggleLockRequest = { requestCount += 1 }
        lockButton.performClick(nil)

        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(
            controlBar.videoState?.isLocked ?? true,
            "ControlBar must not bypass AppDelegate's guarded lock entry"
        )
        XCTAssertEqual(
            lockButton.state,
            .off,
            "A refused request must undo the toggle button's optimistic state"
        )
        XCTAssertEqual(
            lockButton.accessibilityValue() as? String,
            "Unlocked"
        )
        XCTAssertEqual(
            lockButton.accessibilityLabel(),
            "Lock overlay"
        )
    }

    func testMainViewControllerForwardsPreferredHeightAndLockCallbacks() {
        let suiteName = "Reframer.MainControlBarLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = MainViewController(videoState: VideoState(defaults: defaults))
        var lockRequestCount = 0
        var reportedHeights: [CGFloat] = []
        controller.onToggleLockRequest = { lockRequestCount += 1 }
        controller.onControlBarPreferredHeightChange = {
            reportedHeights.append($0)
        }
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(
            x: 0,
            y: 0,
            width: ControlBar.minimumWindowWidth,
            height: 480
        )
        controller.view.layoutSubtreeIfNeeded()
        drainMainQueue()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            controller.controlBar.frame.height,
            ControlBar.compactHeight,
            accuracy: 0.5
        )
        XCTAssertEqual(reportedHeights.last, ControlBar.compactHeight)

        guard let lockButton = descendant(
            withIdentifier: "btn-lock",
            in: controller.controlBar
        ) as? NSButton else {
            return XCTFail("Missing lock button")
        }
        lockButton.performClick(nil)
        XCTAssertEqual(lockRequestCount, 1)
    }

    private func assertEveryControlFits(
        width: CGFloat,
        expectedHeight: CGFloat,
        expectedMode: ControlBar.LayoutMode
    ) {
        let controlBar = makeWorstCaseControlBar(
            width: width,
            height: expectedHeight
        )
        XCTAssertEqual(controlBar.layoutMode, expectedMode)
        assertEveryControlIsInside(controlBar)
        assertControlsDoNotOverlap(in: controlBar)
        assertLongFrameMetadataFits(in: controlBar)
    }

    private func makeWorstCaseControlBar(
        width: CGFloat,
        height: CGFloat
    ) -> ControlBar {
        let suiteName = "Reframer.ControlBarLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let state = VideoState(defaults: defaults)
        retainedStates.append(state)
        state.totalFrames = 9_876_543
        state.frameNavigationPrecision = .indexing
        state.volume = 0.5
        state.isMuted = false

        let controlBar = ControlBar(
            frame: NSRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        controlBar.videoState = state
        drainMainQueue()
        controlBar.layoutSubtreeIfNeeded()
        return controlBar
    }

    private func assertEveryControlIsInside(_ controlBar: ControlBar) {
        let identifiers = [
            "window-drag-handle",
            "btn-open",
            "btn-step-back",
            "btn-play",
            "btn-step-forward",
            "slider-timeline",
            "field-frame",
            "label-frame-total",
            "field-zoom",
            "label-zoom-pct",
            "button-filter-menu",
            "slider-opacity",
            "field-opacity",
            "btn-mute",
            "slider-volume",
            "btn-lock",
            "btn-reset"
        ]

        for identifier in identifiers {
            guard let view = descendant(withIdentifier: identifier, in: controlBar) else {
                XCTFail("Missing control \(identifier)")
                continue
            }
            XCTAssertFalse(view.isHidden, "\(identifier) should be visible")
            let frame = controlBar.convert(view.bounds, from: view)
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                -0.5,
                "\(identifier) extends before the toolbar"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                controlBar.bounds.maxX + 0.5,
                "\(identifier) extends beyond the toolbar"
            )
            XCTAssertGreaterThanOrEqual(
                frame.minY,
                controlBar.bounds.minY - 0.5,
                "\(identifier) extends below the toolbar"
            )
            XCTAssertLessThanOrEqual(
                frame.maxY,
                controlBar.bounds.maxY + 0.5,
                "\(identifier) extends above the toolbar"
            )
        }

        let expectedAccessibilityRoles: [String: NSAccessibility.Role] = [
            "slider-timeline": .slider,
            "slider-opacity": .slider,
            "slider-volume": .slider,
            "field-frame": .textField,
            "field-zoom": .textField,
            "field-opacity": .textField
        ]
        for (identifier, expectedRole) in expectedAccessibilityRoles {
            let view = descendant(withIdentifier: identifier, in: controlBar)
            XCTAssertEqual(
                view?.accessibilityRole(),
                expectedRole,
                "\(identifier) must expose its native accessibility role"
            )
        }
        for identifier in [
            "slider-timeline",
            "slider-opacity",
            "slider-volume"
        ] {
            guard let slider = descendant(
                withIdentifier: identifier,
                in: controlBar
            ) as? NSSlider else {
                XCTFail("Missing slider \(identifier)")
                continue
            }
            XCTAssertEqual(slider.accessibilityOrientation(), .horizontal)
            XCTAssertEqual(
                (slider.accessibilityMinValue() as? NSNumber)?.doubleValue,
                slider.minValue
            )
            XCTAssertEqual(
                (slider.accessibilityMaxValue() as? NSNumber)?.doubleValue,
                slider.maxValue
            )
            XCTAssertGreaterThanOrEqual(
                slider.bounds.height,
                slider.intrinsicContentSize.height,
                "\(identifier) must not clip its intrinsic slider content"
            )
            XCTAssertGreaterThanOrEqual(
                slider.bounds.height,
                24,
                "\(identifier) must retain the cross-toolchain clipping margin"
            )
            let requiredWidth: CGFloat = identifier == "slider-timeline" ? 80 : 52
            XCTAssertGreaterThanOrEqual(
                slider.bounds.width,
                requiredWidth,
                "\(identifier) must remain operable at the minimum width"
            )
        }
    }

    private func assertLongFrameMetadataFits(in controlBar: ControlBar) {
        guard let totalLabel = descendant(
            withIdentifier: "label-frame-total",
            in: controlBar
        ) as? NSTextField else {
            return XCTFail("Missing frame total label")
        }
        XCTAssertEqual(totalLabel.stringValue, "/ ~9876543 · idx")
        XCTAssertLessThanOrEqual(
            totalLabel.attributedStringValue.size().width,
            totalLabel.bounds.width + 0.5,
            "Long frame-count metadata should not clip at the minimum width"
        )
    }

    private func assertControlsDoNotOverlap(in controlBar: ControlBar) {
        let identifiers = [
            "window-drag-handle",
            "btn-open",
            "btn-step-back",
            "btn-play",
            "btn-step-forward",
            "slider-timeline",
            "field-frame",
            "label-frame-total",
            "field-zoom",
            "label-zoom-pct",
            "button-filter-menu",
            "slider-opacity",
            "field-opacity",
            "btn-mute",
            "slider-volume",
            "btn-lock",
            "btn-reset"
        ]
        let controls = identifiers.compactMap { identifier -> (String, NSRect)? in
            guard let view = descendant(
                withIdentifier: identifier,
                in: controlBar
            ) else {
                return nil
            }
            return (identifier, controlBar.convert(view.bounds, from: view))
        }

        for firstIndex in controls.indices {
            for secondIndex in controls.indices where secondIndex > firstIndex {
                let first = controls[firstIndex]
                let second = controls[secondIndex]
                let intersection = first.1.intersection(second.1)
                XCTAssertTrue(
                    intersection.isNull || intersection.width <= 0.5 ||
                        intersection.height <= 0.5,
                    "\(first.0) overlaps \(second.0): \(intersection)"
                )
            }
        }
    }

    private func ancestorStackIdentifier(of view: NSView?) -> String? {
        var candidate = view?.superview
        while let current = candidate {
            if current is NSStackView,
               let identifier = current.identifier?.rawValue,
               identifier.hasSuffix("control-row") {
                return identifier
            }
            candidate = current.superview
        }
        return nil
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

    private func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}
