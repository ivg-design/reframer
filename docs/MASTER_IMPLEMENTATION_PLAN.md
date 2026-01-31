# Reframer — Master Implementation Plan

**Date**: 2026-01-31
**Status**: Comprehensive Audit & Implementation Plan (Revision 8)
**Target Platform**: macOS 26 (Tahoe) with macOS 15 (Sequoia) fallback
**Input Paradigm**: Mouse + Scroll Wheel + Keyboard (Shift/Cmd modifiers only)

---

## Plan Structure

This plan follows a **verification-first approach** with **integrated documentation**:

1. **Phase 0**: Test Infrastructure — Set up testing framework and fixtures ✅ COMPLETE
2. **Phase 1**: Feature Audit — Verify EVERY feature against spec, document status
3. **Phase 2**: Regression Tests — Create unit/UI tests for working features
4. **Phase 3+**: Implementation — Fix broken features with tests
5. **Ongoing**: Documentation — Maintain DocC user guides for every feature

**NO FEATURE IS ASSUMED TO WORK. Every feature must be verified.**
**FEATURES ARE NOT DONE UNTIL DOCUMENTED.**

---

## Design Decisions (Locked In)

| Decision | Value | Source |
|----------|-------|--------|
| Scroll up direction | Zoom OUT | User confirmed |
| Extra modifiers in inputs | None | FEATURES.md (Shift/Cmd only) |
| Shift required for zoom scroll | Yes | FEATURES.md |
| Cmd+Scroll alone | Does nothing | FEATURES.md specifies Cmd+**Shift**+Scroll only |
| Pan at zoom == 100% | Disabled | Pan only when zoomScale > 1.0 |
| Icons | SF Symbols only | FEATURES.md (no emojis) |
| Theme | Dark mode first | FEATURES.md |

---

## Phase 0: Test Infrastructure

### 0.1 Create Test Targets

**Action**: Add XCTest and XCUITest targets to Xcode project

```
Reframer/
├── Reframer.xcodeproj
├── Reframer/           (app source)
├── ReframerTests/      (unit tests)
└── ReframerUITests/    (UI tests)
```

**Checklist**:
- [ ] Add ReframerTests target (Unit Tests)
- [ ] Add ReframerUITests target (UI Tests)
- [ ] Configure test schemes

### 0.2 Test Fixtures

**Action**: Add bundled test videos

| Fixture | Specs | Purpose |
|---------|-------|---------|
| `test_30fps_2s.mp4` | 30fps, 2 seconds, 60 frames, 16:9 | Standard playback |
| `test_60fps_5s.mp4` | 60fps, 5 seconds, 300 frames, 16:9 | High framerate |
| `test_4x3_1s.mp4` | 30fps, 1 second, 4:3 aspect | Aspect ratio handling |

**Checklist**:
- [ ] Create/obtain test fixtures
- [ ] Add to test bundle resources
- [ ] Verify fixtures load in tests

### 0.3 Test Helpers

**Action**: Create test infrastructure code

```swift
// ReframerTests/TestHelpers.swift
import AVFoundation
import XCTest

class VideoTestHelper {
    static func loadFixture(_ name: String) async throws -> (AVPlayer, duration: Double, fps: Double) {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "mp4") else {
            throw TestError.fixtureNotFound(name)
        }
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let fps = try await Double(track.load(.nominalFrameRate))
        let player = AVPlayer(url: url)
        return (player, duration, fps)
    }
}
```

**Checklist**:
- [ ] Create TestHelpers.swift
- [ ] Create VideoTestHelper class
- [ ] Add launch argument for deterministic test state

### 0.4 Update Deployment Target

**Location**: `project.pbxproj`

**Required**: `MACOSX_DEPLOYMENT_TARGET = 15.0` for BOTH Debug AND Release

**Checklist**:
- [ ] Update Debug configuration to 15.0
- [ ] Update Release configuration to 15.0
- [ ] Verify build succeeds

---

## Phase 1: Feature Audit

**EVERY feature from FEATURES.md must be verified. No assumptions.**

### Audit Process

For each feature:
1. **Locate** — Find the code that implements it
2. **Test** — Manually verify it works per spec
3. **Status** — Mark as WORKING / BROKEN / PARTIAL / MISSING
4. **Evidence** — Document what was tested and result

---

### 1.1 Core Window Behavior

#### F-CW-001: Transparent, frameless window (no open/close/minimize buttons)

| Attribute | Value |
|-----------|-------|
| **Location** | `AppDelegate.swift` window setup |
| **Verification** | Launch app, inspect window chrome |
| **Expected** | No title bar, no traffic light buttons, transparent background |
| **Status** | ⬜ PENDING |
| **Test ID** | `W-001` |

**Manual Test**:
1. Launch app
2. Verify no close/minimize/zoom buttons visible
3. Verify window background is transparent (content behind visible)

**Unit Test** (if working):
```swift
func testWindowIsFrameless() {
    let window = NSApp.windows.first!
    XCTAssertEqual(window.styleMask, [.borderless, .resizable])
    XCTAssertFalse(window.titlebarAppearsTransparent)
    XCTAssertTrue(window.isOpaque == false)
    XCTAssertEqual(window.backgroundColor, .clear)
}
```

---

#### F-CW-002: Always-on-top by default (with toggle)

| Attribute | Value |
|-----------|-------|
| **Location** | `AppDelegate.swift`, `VideoState.swift` |
| **Verification** | Check window level on launch, toggle pin button |
| **Expected** | Default level = `.floating`, toggle changes to `.normal` |
| **Status** | ⬜ PENDING |
| **Test ID** | `W-002` |

**Manual Test**:
1. Launch app
2. Open another app window
3. Verify Reframer stays on top
4. Click pin/float toggle
5. Verify other windows can now cover Reframer

**Unit Test**:
```swift
func testAlwaysOnTopDefault() {
    let window = NSApp.windows.first!
    XCTAssertEqual(window.level, .floating)
}

func testAlwaysOnTopToggle() {
    videoState.isPinned = false
    XCTAssertEqual(window.level, .normal)
    videoState.isPinned = true
    XCTAssertEqual(window.level, .floating)
}
```

---

#### F-CW-003: Resizable window via native drag handles

| Attribute | Value |
|-----------|-------|
| **Location** | Window style mask |
| **Verification** | Drag window edges/corners |
| **Expected** | Window resizes, minimum size enforced |
| **Status** | ⬜ PENDING |
| **Test ID** | `W-003` |

**Manual Test**:
1. Hover over window edge — cursor should change to resize cursor
2. Drag edge — window should resize
3. Try to resize below minimum — should be prevented

---

#### F-CW-004: Draggable via control bar OR bottom-right handle

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift`, `ContentView.swift` (drag handle) |
| **Verification** | Drag on control bar empty space, drag on corner handle |
| **Expected** | Window moves when dragging empty space or handle |
| **Status** | ⬜ PENDING |
| **Test ID** | `W-004`, `W-005` |

**Manual Test**:
1. Drag on empty space between controls — window should move
2. Drag on a button — button should respond, NOT move window
3. Drag on bottom-right handle — window should move
4. Handle should show visual feedback on hover

---

#### F-CW-005: Rounded corners (macOS native)

| Attribute | Value |
|-----------|-------|
| **Location** | Window/view corner radius |
| **Verification** | Visual inspection |
| **Expected** | Corners are rounded |
| **Status** | ⬜ PENDING |
| **Test ID** | `W-006` |

---

#### F-CW-006: Install to /Applications prompt

| Attribute | Value |
|-----------|-------|
| **Location** | `AppDelegate.swift` `ensureInstalledInApplications()` |
| **Verification** | Run from Downloads folder |
| **Expected** | Alert prompts to move to /Applications |
| **Status** | ⬜ PENDING |
| **Test ID** | `W-007` |

---

### 1.2 Video Playback

#### F-VP-001: Load video files (mp4, webm, mov, avi, mkv, m4v, prores, hevc, av1)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoFormats.swift`, `DropZoneView.swift` |
| **Verification** | Check `supportedTypes`, test actual file loading |
| **Expected** | All listed formats supported |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-001` |

**Unit Test**:
```swift
func testSupportedFormats() {
    let expected = ["mp4", "webm", "mov", "avi", "mkv", "m4v"]
    for ext in expected {
        XCTAssertTrue(VideoFormats.isSupported(ext), "\(ext) should be supported")
    }
}
```

---

#### F-VP-002: Play/pause toggle

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoState.swift`, `VideoPlayerView.swift` |
| **Verification** | Load video, click play, click pause |
| **Expected** | Playback starts/stops, button state updates |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-002` |

---

#### F-VP-003: Timeline scrubber (no lag, high performance)

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift` slider, `VideoPlayerView.swift` seek |
| **Verification** | Drag slider, observe frame updates |
| **Expected** | Frame updates continuously during drag, not just on release |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-003` |

**Critical**: Must use fast seek during drag, frame-accurate on release.

---

#### F-VP-004: Frame-accurate playback (frame-by-frame stepping)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoPlayerView.swift` step methods |
| **Verification** | Step forward/back, verify time delta = 1/fps |
| **Expected** | Each step moves exactly one frame |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-004` |

**Unit Test**:
```swift
func testFrameStep() async throws {
    let (player, _, fps) = try await VideoTestHelper.loadFixture("test_30fps_2s")
    let frameDuration = 1.0 / fps
    let startTime = player.currentTime().seconds

    videoState.stepFrame(forward: true)

    let endTime = player.currentTime().seconds
    XCTAssertEqual(endTime - startTime, frameDuration, accuracy: 0.001)
}
```

---

#### F-VP-005: Frame number overlay (upper-left corner)

| Attribute | Value |
|-----------|-------|
| **Location** | `OverlayViews.swift` |
| **Verification** | Load video, check overlay position and content |
| **Expected** | Shows "Frame X / Y" in upper-left, updates on seek/play |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-005` |

---

#### F-VP-006: Frame number input with arrow stepping

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift`, `NumericInputField.swift` |
| **Verification** | Focus input, press arrows with/without Shift |
| **Expected** | Arrow = ±1 frame, Shift+Arrow = ±10 frames |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-006` |

---

#### F-VP-007: Auto-apply increments (Enter/Esc defocuses and returns focus to previous app)

| Attribute | Value |
|-----------|-------|
| **Location** | `NumericInputField.swift`, `FocusReturnManager.swift` |
| **Verification** | Focus input, change value, press Enter or Esc |
| **Expected** | Value applies immediately, Enter/Esc defocuses, previous app regains focus |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-007` |

---

#### F-VP-008: Muted by default, volume control minimized

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoState.swift`, `ControlBarView.swift` |
| **Verification** | Load video, check volume state |
| **Expected** | Volume = 0 or muted by default, volume control exists |
| **Status** | ⬜ PENDING |
| **Test ID** | `V-008` |

---

### 1.3 Zoom & Pan

#### F-ZP-001: Zoom via Shift+Scroll (5%) and Cmd+Shift+Scroll (0.1%)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoPlayerView.swift` scrollWheel handler |
| **Verification** | Shift+scroll, Cmd+Shift+scroll |
| **Expected** | Shift = 5% steps, Cmd+Shift = 0.1% steps, Scroll UP = zoom OUT |
| **Status** | ⬜ PENDING |
| **Test ID** | `Z-001`, `Z-002`, `M-002`, `M-003` |

---

#### F-ZP-002: Pan when zoomed (click+drag)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoPlayerView.swift` mouse handlers |
| **Verification** | Zoom > 100%, drag video |
| **Expected** | Video pans. At 100% zoom, drag does nothing |
| **Status** | ⬜ PENDING |
| **Test ID** | `Z-004`, `M-004` |

---

#### F-ZP-003: Zoom scales from video top-left corner

| Attribute | Value |
|-----------|-------|
| **Location** | Zoom transform anchor |
| **Verification** | Zoom in, observe which corner stays fixed |
| **Expected** | Video top-left stays anchored, other edges expand |
| **Status** | ⬜ PENDING |
| **Test ID** | `Z-003` |

---

#### F-ZP-004: Zoom percentage overlay

| Attribute | Value |
|-----------|-------|
| **Location** | `OverlayViews.swift` |
| **Verification** | Zoom in/out, check overlay |
| **Expected** | Shows zoom percentage, updates in real-time |
| **Status** | ⬜ PENDING |
| **Test ID** | `Z-005` |

---

#### F-ZP-005: Zoom input with arrow stepping (1%, Shift=10%, Cmd=0.1%)

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift`, `NumericInputField.swift` |
| **Verification** | Focus zoom input, press arrows with modifiers |
| **Expected** | Arrow = ±1%, Shift = ±10%, Cmd = ±0.1% |
| **Status** | ⬜ PENDING |
| **Test ID** | `Z-006` |

---

#### F-ZP-006: Reset view button

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift`, `VideoState.swift` |
| **Verification** | Zoom and pan, click reset |
| **Expected** | Zoom = 100%, pan = 0 |
| **Status** | ⬜ PENDING |
| **Test ID** | `Z-007` |

---

### 1.4 Opacity

#### F-OP-001: Opacity slider with input (arrow = 1%, Shift = 10%)

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift`, `NumericInputField.swift` |
| **Verification** | Adjust slider, use input arrows |
| **Expected** | Video opacity changes, arrow = ±1%, Shift = ±10% |
| **Status** | ⬜ PENDING |
| **Test ID** | `O-001` |

---

#### F-OP-002: Opacity range 2% to 100%

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoState.swift`, `NumericInputField.swift` |
| **Verification** | Try to set opacity below 2% |
| **Expected** | Clamped to 2% minimum |
| **Status** | ⬜ PENDING |
| **Test ID** | `O-002` |

**Unit Test**:
```swift
func testOpacityMinimum() {
    videoState.opacity = 0.0
    XCTAssertEqual(videoState.opacity, 0.02) // 2%
}
```

---

### 1.5 Lock/Ghost Mode

#### F-LK-001: Lock toggle makes video click-through

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoState.swift`, main window setup |
| **Verification** | Toggle lock, try to click/drag/scroll on video |
| **Expected** | Video area ignores all mouse events, clicks pass through to apps below |
| **Status** | ⬜ PENDING |
| **Test ID** | `L-001` |

---

#### F-LK-002: Controls remain interactive when locked

| Attribute | Value |
|-----------|-------|
| **Location** | Control window setup |
| **Verification** | Lock mode on, click controls |
| **Expected** | All controls still respond (play, zoom, lock toggle, etc.) |
| **Status** | ⬜ PENDING |
| **Test ID** | `L-002` |

---

#### F-LK-003: Window move/resize disabled when locked

| Attribute | Value |
|-----------|-------|
| **Location** | Drag handlers, resize handlers |
| **Verification** | Lock mode on, try to drag/resize |
| **Expected** | Window cannot move or resize |
| **Status** | ⬜ PENDING |
| **Test ID** | `L-003` |

---

#### F-LK-004: Visual lock indicator (SF Symbols icon)

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift` lock button |
| **Verification** | Toggle lock, check icon |
| **Expected** | Icon changes between locked/unlocked states, uses SF Symbols |
| **Status** | ⬜ PENDING |
| **Test ID** | `L-004` |

---

### 1.6 Keyboard Shortcuts (Local)

#### F-KL-001: Left/Right Arrow = Frame step (Shift = 10 frames)

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Press arrows with/without Shift |
| **Expected** | Arrow = 1 frame, Shift+Arrow = 10 frames |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-001` |

---

#### F-KL-002: Up/Down Arrow = Zoom (5%, Shift = 10%)

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Press arrows with/without Shift |
| **Expected** | Arrow = 5%, Shift+Arrow = 10% |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-002` |

---

#### F-KL-003: +/- = Zoom in/out

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Press + and - |
| **Expected** | Zoom increases/decreases |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-002` |

---

#### F-KL-004: 0 = Reset zoom to 100%

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Zoom to 200%, press 0 |
| **Expected** | Zoom = 100% |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-003` |

---

#### F-KL-005: R = Reset view (zoom + pan)

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Zoom and pan, press R |
| **Expected** | Zoom = 100%, pan = 0 |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-003` |

---

#### F-KL-006: L = Toggle lock

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Press L |
| **Expected** | Lock toggles |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-004` |

---

#### F-KL-007: H or ? = Toggle help

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Press H or Shift+/ |
| **Expected** | Help modal appears/disappears |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-004` |

---

#### F-KL-008: Cmd+O = Open file dialog

| Attribute | Value |
|-----------|-------|
| **Location** | Keyboard handler |
| **Verification** | Press Cmd+O |
| **Expected** | File open dialog appears |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-005` |

---

#### F-KL-009: Esc/Enter in inputs = Defocus and return focus

| Attribute | Value |
|-----------|-------|
| **Location** | `NumericInputField.swift`, `FocusReturnManager.swift` |
| **Verification** | Focus input, press Esc or Enter |
| **Expected** | Input loses focus, previous app regains focus |
| **Status** | ⬜ PENDING |
| **Test ID** | `K-006` |

---

### 1.7 Keyboard Shortcuts (Global)

#### F-KG-001: Cmd+Shift+L = Toggle lock (works when app not focused)

| Attribute | Value |
|-----------|-------|
| **Location** | Global keyboard monitor |
| **Verification** | Focus another app, press Cmd+Shift+L |
| **Expected** | Lock toggles in Reframer |
| **Status** | ⬜ PENDING |
| **Test ID** | `KG-001` |

**Note**: Requires Input Monitoring permission.

---

#### F-KG-002: Cmd+PageUp/PageDown = Frame step (Shift = 10 frames)

| Attribute | Value |
|-----------|-------|
| **Location** | Global keyboard monitor |
| **Verification** | Focus another app, press Cmd+PageUp/PageDown |
| **Expected** | Frame steps in Reframer |
| **Status** | ⬜ PENDING |
| **Test ID** | `KG-002` |

---

### 1.8 Mouse/Scroll Controls

#### F-MS-001: Scroll wheel = Frame step (disabled when locked)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoPlayerView.swift` scrollWheel |
| **Verification** | Scroll without modifiers |
| **Expected** | Frame steps forward/back. Does nothing when locked. |
| **Status** | ⬜ PENDING |
| **Test ID** | `M-001` |

---

#### F-MS-002: Shift+Scroll = Zoom 5% (disabled when locked)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoPlayerView.swift` scrollWheel |
| **Verification** | Shift+scroll |
| **Expected** | Zoom changes 5%. Scroll UP = zoom OUT. Does nothing when locked. |
| **Status** | ⬜ PENDING |
| **Test ID** | `M-002` |

---

#### F-MS-003: Cmd+Shift+Scroll = Zoom 0.1% (disabled when locked)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoPlayerView.swift` scrollWheel |
| **Verification** | Cmd+Shift+scroll |
| **Expected** | Zoom changes 0.1%. Does nothing when locked. |
| **Status** | ⬜ PENDING |
| **Test ID** | `M-003` |

---

#### F-MS-004: Click+drag on video = Pan (disabled when locked)

| Attribute | Value |
|-----------|-------|
| **Location** | `VideoPlayerView.swift` mouse handlers |
| **Verification** | Zoom > 100%, drag video |
| **Expected** | Video pans. Does nothing when locked or at 100% zoom. |
| **Status** | ⬜ PENDING |
| **Test ID** | `M-004` |

---

#### F-MS-005: Click+drag on control bar = Move window (disabled when locked)

| Attribute | Value |
|-----------|-------|
| **Location** | Control bar drag handling |
| **Verification** | Drag on empty control bar space |
| **Expected** | Window moves. Does nothing when locked. |
| **Status** | ⬜ PENDING |
| **Test ID** | `M-005` |

---

#### F-MS-006: Click+drag on edges/corners = Resize (disabled when locked)

| Attribute | Value |
|-----------|-------|
| **Location** | Window resize handling |
| **Verification** | Drag window edges |
| **Expected** | Window resizes. Does nothing when locked. |
| **Status** | ⬜ PENDING |
| **Test ID** | `M-006` |

---

### 1.9 UI Elements

#### F-UI-001: Drop zone on launch (click or Cmd+O to open)

| Attribute | Value |
|-----------|-------|
| **Location** | `DropZoneView.swift` |
| **Verification** | Launch app without file |
| **Expected** | Drop zone visible, clickable, accepts drag & drop |
| **Status** | ⬜ PENDING |
| **Test ID** | `UI-001` |

---

#### F-UI-002: Liquid glass design (Tahoe style, dark mode)

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift`, materials |
| **Verification** | Visual inspection |
| **Expected** | Tahoe: glassEffect. Sequoia: ultraThinMaterial. Dark mode. |
| **Status** | ⬜ PENDING |
| **Test ID** | `UI-002` |

---

#### F-UI-003: Control bar with all playback controls

| Attribute | Value |
|-----------|-------|
| **Location** | `ControlBarView.swift` |
| **Verification** | Visual inspection |
| **Expected** | Contains: play/pause, timeline, frame input, zoom input, opacity, lock, help |
| **Status** | ⬜ PENDING |
| **Test ID** | (implicit) |

---

#### F-UI-004: Help modal with all shortcuts listed

| Attribute | Value |
|-----------|-------|
| **Location** | `HelpModalView.swift` |
| **Verification** | Open help, check content |
| **Expected** | All shortcuts from FEATURES.md are listed |
| **Status** | ⬜ PENDING |
| **Test ID** | `UI-003` |

---

#### F-UI-005: Minimal overlays (frame/zoom)

| Attribute | Value |
|-----------|-------|
| **Location** | `OverlayViews.swift` |
| **Verification** | Visual inspection |
| **Expected** | Small, non-intrusive, positioned in corners |
| **Status** | ⬜ PENDING |
| **Test ID** | `UI-004` |

---

#### F-UI-006: SF Symbols for all icons (no emojis)

| Attribute | Value |
|-----------|-------|
| **Location** | All button/icon usage |
| **Verification** | Code inspection, visual inspection |
| **Expected** | All icons use `Image(systemName:)`, no emoji characters |
| **Status** | ⬜ PENDING |
| **Test ID** | (new) |

---

### 1.10 File Handling

#### F-FH-001: Open file dialog with video filter

| Attribute | Value |
|-----------|-------|
| **Location** | File open panel setup |
| **Verification** | Cmd+O, check allowed types |
| **Expected** | Only video formats selectable |
| **Status** | ⬜ PENDING |
| **Test ID** | `F-101` |

---

#### F-FH-002: Drag & drop video files

| Attribute | Value |
|-----------|-------|
| **Location** | `DropZoneView.swift` |
| **Verification** | Drag video from Finder onto window |
| **Expected** | Video loads and plays |
| **Status** | ⬜ PENDING |
| **Test ID** | `F-102` |

---

#### F-FH-003: Reject unsupported files

| Attribute | Value |
|-----------|-------|
| **Location** | `DropZoneView.swift`, file validation |
| **Verification** | Drop non-video file |
| **Expected** | File rejected, app stays in drop state |
| **Status** | ⬜ PENDING |
| **Test ID** | `F-103` |

---

### 1.11 Transparency

#### F-TR-001: Video area 100% transparent background

| Attribute | Value |
|-----------|-------|
| **Location** | Main window, video view |
| **Verification** | Load video, check background |
| **Expected** | Only video pixels visible, background is fully transparent |
| **Status** | ⬜ PENDING |
| **Test ID** | `T-001` |

---

#### F-TR-002: Opacity affects only video pixels

| Attribute | Value |
|-----------|-------|
| **Location** | Opacity application |
| **Verification** | Set opacity to 50%, check background |
| **Expected** | Video pixels at 50%, background still transparent |
| **Status** | ⬜ PENDING |
| **Test ID** | `T-002` |

---

### 1.12 App Icon

#### F-IC-001: Custom application icon

| Attribute | Value |
|-----------|-------|
| **Location** | Assets.xcassets/AppIcon |
| **Verification** | Check Dock icon |
| **Expected** | Custom icon (not default SwiftUI icon) |
| **Status** | ⬜ PENDING |
| **Test ID** | `I-001` |

---

## Phase 1 Summary: Audit Checklist

| Category | Features | Tests |
|----------|----------|-------|
| Core Window | 6 | W-001 to W-007 |
| Video Playback | 8 | V-001 to V-008 |
| Zoom & Pan | 6 | Z-001 to Z-007 |
| Opacity | 2 | O-001, O-002 |
| Lock Mode | 4 | L-001 to L-004 |
| Keyboard Local | 9 | K-001 to K-006 |
| Keyboard Global | 2 | KG-001, KG-002 |
| Mouse/Scroll | 6 | M-001 to M-006 |
| UI Elements | 6 | UI-001 to UI-004 |
| File Handling | 3 | F-101 to F-103 |
| Transparency | 2 | T-001, T-002 |
| App Icon | 1 | I-001 |
| **TOTAL** | **55** | |

---

## Phase 2: Regression Test Suite

After Phase 1 audit, create automated tests for all WORKING features.

### 2.1 Unit Tests (ReframerTests)

For each feature marked WORKING in Phase 1:

```swift
// ReframerTests/VideoStateTests.swift
import XCTest
@testable import Reframer

final class VideoStateTests: XCTestCase {
    var videoState: VideoState!

    override func setUp() {
        videoState = VideoState()
    }

    // F-OP-002: Opacity minimum
    func testOpacityClampedToMinimum() {
        videoState.opacity = 0.0
        XCTAssertGreaterThanOrEqual(videoState.opacity, 0.02)
    }

    // F-ZP-006: Reset view
    func testResetView() {
        videoState.zoomScale = 2.0
        videoState.panOffset = CGPoint(x: 100, y: 100)
        videoState.resetView()
        XCTAssertEqual(videoState.zoomScale, 1.0)
        XCTAssertEqual(videoState.panOffset, .zero)
    }

    // F-LK-001: Lock state
    func testLockToggle() {
        XCTAssertFalse(videoState.isLocked)
        videoState.isLocked.toggle()
        XCTAssertTrue(videoState.isLocked)
    }
}
```

### 2.2 UI Tests (ReframerUITests)

```swift
// ReframerUITests/ControlsUITests.swift
import XCTest

final class ControlsUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--uitesting", "--fixture=test_30fps_2s"]
        app.launch()
    }

    // F-VP-002: Play/pause
    func testPlayPauseToggle() {
        let playButton = app.buttons["playPauseButton"]
        XCTAssertTrue(playButton.exists)
        playButton.tap()
        // Verify state changed
    }

    // F-UI-001: Drop zone
    func testDropZoneVisible() {
        // Launch without fixture
        let freshApp = XCUIApplication()
        freshApp.launchArguments = ["--uitesting"]
        freshApp.launch()

        let dropZone = freshApp.otherElements["dropZone"]
        XCTAssertTrue(dropZone.exists)
    }
}
```

### 2.3 Lock Mode + Scroll Tests (Gap Coverage)

```swift
// Tests for lock mode disabling scroll controls (identified gap)
func testScrollDisabledWhenLocked() {
    videoState.isLocked = true
    let initialFrame = videoState.currentFrame

    // Simulate scroll event
    // ...

    XCTAssertEqual(videoState.currentFrame, initialFrame, "Scroll should be disabled when locked")
}

func testZoomScrollDisabledWhenLocked() {
    videoState.isLocked = true
    let initialZoom = videoState.zoomScale

    // Simulate Shift+scroll
    // ...

    XCTAssertEqual(videoState.zoomScale, initialZoom, "Zoom scroll should be disabled when locked")
}
```

### 2.4 CI Integration

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build and Test
        run: |
          xcodebuild test \
            -project Reframer/Reframer.xcodeproj \
            -scheme Reframer \
            -destination 'platform=macOS'
```

---

## Phase 3+: Implementation Fixes

After Phase 1 identifies all BROKEN/PARTIAL/MISSING features, implement fixes.

### Known Issues (From Previous Analysis)

These are **suspected** issues from prior code review. Phase 1 audit will confirm/deny each:

| # | Issue | Status | Phase 1 Verification |
|---|-------|--------|---------------------|
| 1 | Drag & drop API wrong | SUSPECTED | Test F-FH-002 |
| 2 | Entitlements incomplete | SUSPECTED | Test F-FH-002 |
| 3 | Keyboard monitor window-scoped | SUSPECTED | Test F-KL-* from control window |
| 4 | Hit-testing swallows controls | SUSPECTED | Test F-CW-004, F-MS-005 |
| 5 | Input field modifiers missing | SUSPECTED | Test F-VP-006, F-ZP-005 |
| 6 | Global shortcut permission UX | SUSPECTED | Test F-KG-* |
| 7 | Control window height clips | SUSPECTED | Visual inspection |

### Implementation Order

After Phase 1 audit completes:

1. **Critical** — Features that block basic functionality
2. **High** — Features that significantly impact UX
3. **Medium** — Features that are inconvenient but have workarounds
4. **Low** — Polish and edge cases

Each fix must:
1. Have a failing test FIRST (from Phase 2)
2. Implement the fix
3. Pass the test
4. Not break any other regression tests

---

## Implementation Checklist

### Phase 0: Test Infrastructure ✅ COMPLETE
- [x] 0.1 Create ReframerTests target
- [x] 0.2 Create ReframerUITests target
- [x] 0.3 Add test fixture videos (test_30fps_2s.mp4, test_60fps_5s.mp4, test_4x3_1s.mp4)
- [x] 0.4 Create TestHelpers.swift
- [x] 0.5 Update deployment target to 15.0 (Debug + Release) — Already configured

**Phase 0 Results:**
- 38 unit tests passing (VideoStateTests: 22, VideoFormatsTests: 16)
- Test fixtures bundled in ReframerTests target
- All test targets configured and building

### Phase 1: Feature Audit
- [ ] 1.1 Audit Core Window (6 features)
- [ ] 1.2 Audit Video Playback (8 features)
- [ ] 1.3 Audit Zoom & Pan (6 features)
- [ ] 1.4 Audit Opacity (2 features)
- [ ] 1.5 Audit Lock Mode (4 features)
- [ ] 1.6 Audit Keyboard Local (9 features)
- [ ] 1.7 Audit Keyboard Global (2 features)
- [ ] 1.8 Audit Mouse/Scroll (6 features)
- [ ] 1.9 Audit UI Elements (6 features)
- [ ] 1.10 Audit File Handling (3 features)
- [ ] 1.11 Audit Transparency (2 features)
- [ ] 1.12 Audit App Icon (1 feature)
- [ ] 1.13 Document all statuses in this plan

### Phase 2: Regression Tests
- [ ] 2.1 Unit tests for all WORKING features
- [ ] 2.2 UI tests for all WORKING features
- [ ] 2.3 Lock mode + scroll interaction tests (gap)
- [ ] 2.4 CI integration

### Phase 3+: Implementation
- [ ] Fix all BROKEN features (TBD after Phase 1)
- [ ] Implement all MISSING features (TBD after Phase 1)
- [ ] Complete all PARTIAL features (TBD after Phase 1)

---

## Audit Status Summary

**To be filled in during Phase 1 execution:**

| Status | Count | Features |
|--------|-------|----------|
| ✅ WORKING | 0 | |
| ❌ BROKEN | 0 | |
| ⚠️ PARTIAL | 0 | |
| 🚫 MISSING | 0 | |
| ⬜ PENDING | 55 | All |

---

## Documentation Workflow (DocC)

### Overview

User-facing documentation is maintained alongside code using **Apple DocC** (Articles + Tutorials, not API docs). Every feature implementation includes corresponding documentation updates.

### Documentation Structure

```
Reframer/
├── Reframer.docc/               # DocC Documentation Catalog
│   ├── Reframer.md              # Landing page / overview
│   ├── GettingStarted.md        # Installation & first launch
│   ├── Articles/                # How-to guides
│   │   ├── LoadingVideos.md
│   │   ├── PlaybackControls.md
│   │   ├── ZoomAndPan.md
│   │   ├── OpacityControl.md
│   │   ├── LockMode.md
│   │   ├── KeyboardShortcuts.md
│   │   └── Troubleshooting.md
│   ├── Tutorials/               # Step-by-step walkthroughs (optional)
│   │   └── TableOfContents.tutorial
│   └── Resources/               # Images, screenshots
│       └── *.png
└── docs/
    └── docc-export/             # Generated HTML output (git-ignored)
```

### Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Article files | PascalCase.md | `ZoomAndPan.md` |
| Tutorial files | PascalCase.tutorial | `QuickStart.tutorial` |
| Image assets | feature-description@2x.png | `zoom-controls-overview@2x.png` |
| Section headers | Sentence case | "How to load a video" |

### Article Template

Each feature article should include:

```markdown
# Feature Name

Brief description of what this feature does.

## How to Use

Step-by-step instructions with numbered lists.

## Expected Behavior

What the user should see/experience.

## Edge Cases

Special conditions, limits, or unusual scenarios.

## Troubleshooting

Common issues and their solutions.

## Related

Links to related features/articles.
```

### Definition of Done (DoD)

A feature is **DONE** when:
- [ ] Code implemented and tested
- [ ] Unit/UI tests passing
- [ ] DocC article created or updated
- [ ] Screenshots added (if UI change)
- [ ] Article reviewed for accuracy

### CI/Build Integration

#### Local DocC Build

```bash
# Build documentation
xcodebuild docbuild \
  -scheme Reframer \
  -destination 'platform=macOS' \
  -derivedDataPath .build

# Export to static HTML
$(xcrun --find docc) process-archive transform-for-static-hosting \
  .build/Build/Products/Debug/Reframer.doccarchive \
  --output-path docs/docc-export \
  --hosting-base-path /reframer
```

#### GitHub Actions (CI)

```yaml
# .github/workflows/docs.yml
name: Build Documentation
on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  build-docs:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Build DocC
        run: |
          xcodebuild docbuild \
            -scheme Reframer \
            -destination 'platform=macOS' \
            -derivedDataPath .build

      - name: Export Static HTML
        run: |
          $(xcrun --find docc) process-archive transform-for-static-hosting \
            .build/Build/Products/Debug/Reframer.doccarchive \
            --output-path docs/docc-export \
            --hosting-base-path /reframer

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs/docc-export
```

### Documentation Locations

| Location | Purpose |
|----------|---------|
| `Reframer.docc/` | Source files (versioned in repo) |
| `docs/docc-export/` | Generated HTML (git-ignored, built at release) |
| GitHub Pages | Public website (auto-deployed) |
| In-app Help | Future: Bundle .doccarchive in app for offline access |

### Documentation Checklist

- [ ] Create `Reframer.docc/` documentation catalog
- [ ] Write landing page (`Reframer.md`)
- [ ] Write Getting Started guide
- [ ] Add articles for each feature category
- [ ] Add screenshots for key UI elements
- [ ] Configure CI to build/deploy docs on release
- [ ] Add .gitignore entry for `docs/docc-export/`

---

*Master Implementation Plan — Revision 8 — January 31, 2026*
*Verification-First Approach with Regression Testing + DocC Documentation*
