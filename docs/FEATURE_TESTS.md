# VideoOverlay — Practical Test Plan

This document lists **practical automated tests** (unit, integration, and UI) that should be added to conclusively verify every feature in `FEATURES.md`. Each test includes a short method + expected result. Where a feature can’t be validated purely with unit tests, it is called out and mapped to an **XCUITest/UI test** or **integration test**. The goal is full coverage of all functional requirements.

## Test Harness & Fixtures (Foundational)
These are prerequisites that many tests depend on.

### F-001: Bundled fixture videos
- **Type**: Test asset
- **Method**: Add 2–3 short fixtures to test bundle (e.g., 2s @ 30fps, 5s @ 60fps, with known frame counts). Include one with non‑16:9 aspect (e.g., 4:3).
- **Pass**: Fixtures load from bundle reliably in unit + UI tests.

### F-002: Deterministic AVPlayer setup
- **Type**: Integration helper
- **Method**: Provide a test helper to load fixture video and wait for asset/track metadata.
- **Pass**: Helper returns duration, fps, and natural size within timeout.

### F-003: Launch argument hook
- **Type**: Test harness
- **Method**: Add optional launch argument to auto‑open fixture video and start paused.
- **Pass**: App launches into known state, enabling deterministic UI tests.

---

## Core Window Behavior

### W-001: Window is transparent + frameless
- **Type**: UI test
- **Method**: Launch app; assert window has no title bar controls and background is fully transparent (pixel sample of window background behind video area when no video loaded).
- **Pass**: No close/minimize/zoom buttons; background alpha is 0.

### W-002: Always‑on‑top default + toggle
- **Type**: Integration/UI test
- **Method**: Inspect `NSWindow.level` via test hook; toggle pin button and confirm level change.
- **Pass**: Default level = `.floating`; toggle switches to `.normal` and back.

### W-003: Window resizable via native handles
- **Type**: UI test
- **Method**: Programmatically drag window edge/corner; verify frame size changes.
- **Pass**: Size changes; min size honored.

### W-004: Window draggable via control bar area
- **Type**: UI test
- **Method**: Drag on control bar background; verify window origin changes.
- **Pass**: Window moves; position changes consistently.

### W-005: Bottom‑right handle drag works + hitbox
- **Type**: UI test
- **Method**: Hover over handle area; drag within 44×44 area; verify window moves.
- **Pass**: Handle drag works without flicker; cursor feedback appears.

### W-006: Rounded corners visible
- **Type**: UI test
- **Method**: Pixel‑sample corners in screenshots.
- **Pass**: Corners are rounded; no hard corners.

### W-007: Install to /Applications prompt
- **Type**: Integration test
- **Method**: Run from non‑/Applications location and assert alert appears.
- **Pass**: Prompt shows with Move/Cancel options.

---

## Video Playback

### V-001: Supported format load
- **Type**: Unit + integration
- **Method**: `VideoFormats.isSupported` returns true for expected extensions. Load fixtures with matching UTTypes.
- **Pass**: Supported list matches feature list; open dialog filters correctly.

### V-002: Play / pause toggle
- **Type**: Integration/UI test
- **Method**: Load fixture; click Play; verify `isPlaying` true and time advances. Click Pause; time stops.
- **Pass**: State toggles and playback responds.

### V-003: Timeline scrub real‑time
- **Type**: UI test
- **Method**: Drag slider and sample `currentTime`/displayed frame while dragging.
- **Pass**: Video frame changes continuously during drag (not only on release).

### V-004: Frame‑accurate stepping
- **Type**: Integration test
- **Method**: Step forward/back and assert time increases by `1/fps` per step.
- **Pass**: Frame index increments exactly by step amount.

### V-005: Frame overlay display
- **Type**: UI test
- **Method**: Verify overlay text shows currentFrame/totalFrames; updates during playback/seek.
- **Pass**: Overlay updates correctly.

### V-006: Frame input + arrow step
- **Type**: UI test
- **Method**: Focus frame input; press ↑/↓ (and Shift). Assert frame jumps 1 / 10.
- **Pass**: Value changes instantly; no Enter required.

### V-007: Enter/Esc defocus + return focus
- **Type**: UI test
- **Method**: Focus an input; press Enter or Esc. Verify focus leaves input and previous app regains focus.
- **Pass**: Focus restored to previous app; input not active.

### V-008: Muted by default + volume control
- **Type**: Integration test
- **Method**: Load fixture; assert volume 0 and muted state true. Unmute -> volume > 0.
- **Pass**: Muted default and slider works.

---

## Zoom & Pan

### Z-001: Shift+Scroll zoom 5% increments
- **Type**: UI test
- **Method**: Shift‑scroll; verify zoom percentage changes by 5% steps.
- **Pass**: Zoom changes exactly by 5% per tick.

### Z-002: Cmd+Shift+Scroll zoom 0.1% increments
- **Type**: UI test
- **Method**: Cmd+Shift‑scroll; verify zoom changes by 0.1% steps.
- **Pass**: Fine increments are applied.

### Z-003: Zoom anchor = video top‑left
- **Type**: UI/integration
- **Method**: Zoom in; sample video top‑left pixel remains anchored while other edges move.
- **Pass**: Zoom is anchored to video origin, not window.

### Z-004: Pan only when zoomed
- **Type**: UI test
- **Method**: Zoom > 100%; drag video; verify pan offset changes. At 100%, drag does not move.
- **Pass**: Pan works only when zoomed.

### Z-005: Zoom overlay display
- **Type**: UI test
- **Method**: Zoom in/out; verify overlay updates and matches zoom input.
- **Pass**: Overlay matches zoom state.

### Z-006: Zoom input with step modifiers
- **Type**: UI test
- **Method**: Focus zoom input; press ↑/↓ (1%), Shift+↑/↓ (10%), Cmd+↑/↓ (0.1%).
- **Pass**: Input and actual zoom reflect steps.

### Z-007: Reset view button
- **Type**: UI test
- **Method**: Zoom + pan; click reset; verify zoom=100%, pan=0.
- **Pass**: View resets.

---

## Opacity

### O-001: Opacity slider and input
- **Type**: UI test
- **Method**: Set slider to 50%; verify view opacity reflects ~0.5. Use input with arrows for 1%/10%.
- **Pass**: Opacity updates immediately and clamps 2–100%.

### O-002: Min opacity is 2%
- **Type**: Unit + UI
- **Method**: Set input to 0; assert clamped to 2. Slider can’t go below 2%.
- **Pass**: Opacity never below 2%.

---

## Lock / Ghost Mode

### L-001: Lock makes video click‑through
- **Type**: UI test
- **Method**: Toggle lock, then attempt to click/drag video. Verify no pan/zoom/scroll actions occur.
- **Pass**: Video area ignores mouse and scroll.

### L-002: Controls remain interactive when locked
- **Type**: UI test
- **Method**: Lock enabled; click play/pause, toggle lock off via control bar.
- **Pass**: Controls respond while video area is click‑through.

### L-003: Window move/resize disabled when locked
- **Type**: UI test
- **Method**: Lock, drag control bar and window edge; verify window frame unchanged.
- **Pass**: Window cannot move/resize while locked.

### L-004: Visual lock indicator updates
- **Type**: UI test
- **Method**: Toggle lock; check lock icon and status indicator.
- **Pass**: Visual state matches lock state.

---

## Keyboard Shortcuts (Local)

### K-001: Arrow keys frame step
- **Type**: UI test
- **Method**: Focus app; press ←/→ and Shift+←/→.
- **Pass**: Frame increments 1 or 10.

### K-002: Zoom keys
- **Type**: UI test
- **Method**: Press ↑/↓, Shift+↑/↓, +/−.
- **Pass**: Zoom changes 5%/10% and +/- increments.

### K-003: Reset zoom + reset view
- **Type**: UI test
- **Method**: Press 0; verify zoom=100. Press R; verify zoom/pan reset.
- **Pass**: Resets work.

### K-004: Toggle lock and help
- **Type**: UI test
- **Method**: Press L; verify lock toggles. Press H or ?; help appears.
- **Pass**: Shortcuts toggle states.

### K-005: Cmd+O opens dialog
- **Type**: UI test
- **Method**: Press Cmd+O; verify open panel appears.
- **Pass**: Open panel displayed.

### K-006: Esc/Enter defocus inputs
- **Type**: UI test
- **Method**: Focus input; press Esc/Enter. Verify input loses focus and previous app re‑activates.
- **Pass**: Focus behavior correct.

---

## Keyboard Shortcuts (Global)

### KG-001: Cmd+Shift+L toggles lock globally
- **Type**: Integration test
- **Method**: Make another app active, press Cmd+Shift+L via CGEvent. Verify lock toggles in VideoOverlay.
- **Pass**: Lock toggles while app inactive.

### KG-002: Cmd+PageUp/PageDown frame step
- **Type**: Integration test
- **Method**: App inactive; send key events. Verify frame steps by 1 or 10 with Shift.
- **Pass**: Frame changes while locked/inactive.

---

## Mouse/Scroll Controls

### M-001: Scroll wheel frame step
- **Type**: UI test
- **Method**: Scroll without modifiers; verify frame changes forward/back.
- **Pass**: Frame steps as expected.

### M-002: Shift+Scroll zoom
- **Type**: UI test
- **Method**: Shift‑scroll; verify zoom changes by 5% increments.
- **Pass**: Zoom updates correctly.

### M-003: Cmd+Shift+Scroll fine zoom
- **Type**: UI test
- **Method**: Cmd+Shift‑scroll; verify 0.1% increments.
- **Pass**: Fine zoom applied.

### M-004: Drag video pan
- **Type**: UI test
- **Method**: Zoom > 100; drag; verify pan offset changes.
- **Pass**: Pan works.

### M-005: Drag bar to move window
- **Type**: UI test
- **Method**: Drag control bar background; window moves unless locked.
- **Pass**: Move works when unlocked.

### M-006: Drag edges/corners to resize
- **Type**: UI test
- **Method**: Drag edges/corners; frame changes unless locked.
- **Pass**: Resize works when unlocked.

---

## UI Elements

### UI-001: Drop zone visible on launch
- **Type**: UI test
- **Method**: Launch app without file; verify drop zone UI present and clickable.
- **Pass**: Drop zone shown.

### UI-002: Liquid glass visual style
- **Type**: Snapshot test
- **Method**: Snapshot control bar + overlays; compare to baseline images.
- **Pass**: Visual regression matches baseline.

### UI-003: Help modal shows all shortcuts
- **Type**: UI test
- **Method**: Open help; verify all required shortcuts present.
- **Pass**: Help lists all shortcuts.

### UI-004: Overlays minimal + positioned
- **Type**: UI test
- **Method**: Verify frame and zoom overlays exist, small, and top corners.
- **Pass**: Overlays visible and non‑intrusive.

---

## File Handling

### F-101: Open dialog filter
- **Type**: UI test
- **Method**: Cmd+O; verify UTTypes for common video formats.
- **Pass**: Only supported types accepted.

### F-102: Drag & drop
- **Type**: UI test
- **Method**: Drag fixture into window; verify video loads.
- **Pass**: Drop loads and plays.

### F-103: Unsupported file rejection
- **Type**: UI test
- **Method**: Drop unsupported file; verify no load.
- **Pass**: App rejects and remains in drop state.

---

## Custom App Icon

### I-001: App icon present
- **Type**: UI/integration
- **Method**: Inspect `CFBundleIconName` and assets; verify non‑default icon.
- **Pass**: Custom icon exists and displayed in Dock.

---

## Transparency / Overlay Behavior

### T-001: Video area fully transparent background
- **Type**: UI test
- **Method**: Pixel sample outside video content (transparent region) -> alpha = 0.
- **Pass**: Background fully transparent.

### T-002: Opacity affects only video pixels
- **Type**: UI test
- **Method**: Set opacity to 50%; sample video pixels vs background.
- **Pass**: Video pixels alpha adjusted; background remains transparent.

---

## Coverage Matrix (FEATURES.md)
All items in FEATURES.md are covered by at least one test above. Any new feature should add a corresponding test ID.

---

## Notes
- Many of these tests require **XCUITest** and a helper API to read state (e.g., `VideoState`) or expose debug labels/IDs for UI elements.
- UI snapshot tests should be gated under a stable test profile.
- Global shortcut tests require CGEvent injection and may need accessibility permissions on CI/dev machines.
