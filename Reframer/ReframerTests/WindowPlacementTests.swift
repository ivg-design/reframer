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

    func testLegacyVideoFrameEmbedsControlBarWithoutMovingVisibleFootprint() {
        let legacyVideoFrame = NSRect(x: 220, y: 180, width: 1_060, height: 560)

        let composite = WindowPlacement.frameByEmbeddingControlBar(
            legacyVideoFrame,
            controlBarHeight: 48
        )

        XCTAssertEqual(composite, NSRect(x: 220, y: 132, width: 1_060, height: 608))
        XCTAssertEqual(composite.minX, legacyVideoFrame.minX)
        XCTAssertEqual(composite.maxX, legacyVideoFrame.maxX)
        XCTAssertEqual(composite.maxY, legacyVideoFrame.maxY)
    }

    func testLegacyFrameMigrationSanitizesInvalidControlBarHeight() {
        let legacyVideoFrame = NSRect(x: 20, y: 30, width: 640, height: 360)

        XCTAssertEqual(
            WindowPlacement.frameByEmbeddingControlBar(
                legacyVideoFrame,
                controlBarHeight: .infinity
            ),
            legacyVideoFrame
        )
        XCTAssertEqual(
            WindowPlacement.frameByEmbeddingControlBar(
                legacyVideoFrame,
                controlBarHeight: -48
            ),
            legacyVideoFrame
        )
    }

    func testStoredLegacyFrameMigratesExactlyOnce() {
        let legacy = NSRect(x: 100, y: 200, width: 900, height: 500)
        let defaultFrame = NSRect(x: 0, y: 0, width: 640, height: 408)

        let migrated = WindowPlacement.restoredMainFrame(
            savedFrameDescription: NSStringFromRect(legacy),
            savedSchema: 1,
            currentSchema: 2,
            defaultFrame: defaultFrame,
            controlBarHeight: 48
        )
        XCTAssertEqual(
            migrated,
            NSRect(x: 100, y: 152, width: 900, height: 548)
        )

        let restoredAgain = WindowPlacement.restoredMainFrame(
            savedFrameDescription: NSStringFromRect(migrated),
            savedSchema: 2,
            currentSchema: 2,
            defaultFrame: defaultFrame,
            controlBarHeight: 48
        )
        XCTAssertEqual(
            restoredAgain,
            migrated,
            "Persisting schema 2 immediately must prevent a second embed"
        )
    }

    func testCurrentAndMalformedStoredFramesResolveDeterministically() {
        let current = NSRect(x: 120, y: 180, width: 700, height: 520)
        let fallback = NSRect(x: 20, y: 30, width: 640, height: 408)

        XCTAssertEqual(
            WindowPlacement.restoredMainFrame(
                savedFrameDescription: NSStringFromRect(current),
                savedSchema: 2,
                currentSchema: 2,
                defaultFrame: fallback,
                controlBarHeight: 48
            ),
            current
        )
        XCTAssertEqual(
            WindowPlacement.restoredMainFrame(
                savedFrameDescription: "not a frame",
                savedSchema: 1,
                currentSchema: 2,
                defaultFrame: fallback,
                controlBarHeight: 48
            ),
            fallback
        )
        XCTAssertEqual(
            WindowPlacement.restoredMainFrame(
                savedFrameDescription: nil,
                savedSchema: 0,
                currentSchema: 2,
                defaultFrame: fallback,
                controlBarHeight: 48
            ),
            fallback
        )
    }

    func testOverlayPolicyMatrix() {
        XCTAssertEqual(
            OverlayWindowPolicy.resolve(isLocked: false, isAlwaysOnTop: false),
            OverlayWindowPolicy(
                level: .normal,
                ignoresMouseEvents: false,
                isResizable: true,
                isMovable: true
            )
        )
        XCTAssertEqual(
            OverlayWindowPolicy.resolve(isLocked: false, isAlwaysOnTop: true),
            OverlayWindowPolicy(
                level: .floating,
                ignoresMouseEvents: false,
                isResizable: true,
                isMovable: true
            )
        )
        XCTAssertEqual(
            OverlayWindowPolicy.resolve(isLocked: true, isAlwaysOnTop: false),
            OverlayWindowPolicy(
                level: .statusBar,
                ignoresMouseEvents: true,
                isResizable: false,
                isMovable: false
            )
        )
        XCTAssertEqual(
            OverlayWindowPolicy.resolve(isLocked: true, isAlwaysOnTop: true),
            OverlayWindowPolicy(
                level: .statusBar,
                ignoresMouseEvents: true,
                isResizable: false,
                isMovable: false
            )
        )
    }

    func testUnlockRestoresPersistedAlwaysOnTopPreference() {
        let persistedPreference = false
        let locked = OverlayWindowPolicy.resolve(
            isLocked: true,
            isAlwaysOnTop: persistedPreference
        )
        let unlocked = OverlayWindowPolicy.resolve(
            isLocked: false,
            isAlwaysOnTop: persistedPreference
        )

        XCTAssertEqual(locked.level, .statusBar)
        XCTAssertEqual(unlocked.level, .normal)
        XCTAssertTrue(locked.ignoresMouseEvents)
        XCTAssertFalse(unlocked.ignoresMouseEvents)
        XCTAssertFalse(persistedPreference)
    }

    func testLockedLevelCoversApplicationWindowsButYieldsToSystemUI() {
        let locked = OverlayWindowPolicy.resolve(
            isLocked: true,
            isAlwaysOnTop: false
        )

        XCTAssertGreaterThan(locked.level.rawValue, NSWindow.Level.floating.rawValue)
        XCTAssertGreaterThan(locked.level.rawValue, NSWindow.Level.modalPanel.rawValue)
        XCTAssertLessThan(locked.level.rawValue, NSWindow.Level.popUpMenu.rawValue)
        XCTAssertLessThan(locked.level.rawValue, NSWindow.Level.screenSaver.rawValue)
        XCTAssertEqual(
            OverlayWindowPolicy.auxiliaryLevel(
                isLocked: true,
                isAlwaysOnTop: false
            ),
            locked.level,
            "Visible Help and settings panels must be orderable above the locked overlay"
        )
        XCTAssertEqual(
            OverlayWindowPolicy.auxiliaryLevel(
                isLocked: false,
                isAlwaysOnTop: false
            ),
            .normal
        )
    }

    func testLockedFrameGuardRejectsMoveAndResizeUntilUnlock() {
        let lockedFrame = NSRect(x: 100, y: 200, width: 700, height: 500)
        let externallyChanged = NSRect(x: 0, y: 0, width: 640, height: 408)
        var guardState = LockedWindowFrameGuard()

        guardState.updateLockState(isLocked: true, currentFrame: lockedFrame)
        XCTAssertEqual(guardState.lockedFrame, lockedFrame)
        XCTAssertNil(guardState.restorationFrame(for: lockedFrame))
        XCTAssertEqual(
            guardState.restorationFrame(for: externallyChanged),
            lockedFrame
        )

        // Policy reapplication while locked must never adopt a frame written
        // by Accessibility or a delayed window-manager operation.
        guardState.updateLockState(
            isLocked: true,
            currentFrame: externallyChanged
        )
        XCTAssertEqual(guardState.lockedFrame, lockedFrame)

        guardState.updateLockState(
            isLocked: false,
            currentFrame: lockedFrame
        )
        XCTAssertNil(guardState.lockedFrame)
        XCTAssertNil(guardState.restorationFrame(for: externallyChanged))
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

@MainActor
final class WindowPlacementAppKitTests: XCTestCase {
    func testOverlayPolicyAppliesAtomicallyToAppKitWindow() {
        let window = TransparentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 408),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        OverlayWindowPolicy.resolve(
            isLocked: true,
            isAlwaysOnTop: false
        ).apply(to: window)
        XCTAssertEqual(window.level, .statusBar)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isMovable)

        OverlayWindowPolicy.resolve(
            isLocked: false,
            isAlwaysOnTop: false
        ).apply(to: window)
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.isMovable)
    }

    func testVideoAndControlsShareOneCanonicalWindow() {
        let suiteName = "Reframer.SingleWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = VideoState(defaults: defaults)
        let controller = MainViewController(videoState: state)
        let window = TransparentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_060, height: 608),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.windowToDrag = window
        _ = controller.view

        XCTAssertTrue(controller.controlBar.window === window)
        XCTAssertTrue(controller.controlBar.windowToDrag === window)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }
}
