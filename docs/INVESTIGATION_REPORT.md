# VideoOverlay Interaction Failures — Investigation Report

Date: 2026-01-31

## Scope & Method
- Scope: Swift macOS app only (VideoOverlay)
- Method: Static code audit of current repo state (no runtime instrumentation)
- Goal: Identify code-level issues that explain why controls/zoom/pan are not functioning

## Reported Symptoms (from user)
- Zoom not working (sometimes only zoom-out, choppy, or resets)
- No panning
- Buttons and shortcuts appear dead
- Only timeline scrubbing responds
- Window drag works only from tiny bottom-right handle

## Key Findings (Code-Level)

### 1) Control bar drag wrapper likely swallows most control interactions
**Evidence**
- Control bar is wrapped in `WindowDragView` inside a separate control window.
  - `ControlWindowView.swift`: wraps `ControlBarView()` in `WindowDragView { ... }`.
- `WindowDragNSView.hitTest(_:)` returns `self` unless it detects an `NSControl` or `NSTextView` ancestor.
  - `ContentView.swift`: `WindowDragNSView.hitTest` (lines ~158–169).

**Why this breaks controls**
- SwiftUI `Button` and many SwiftUI controls are not `NSControl` subclasses. The hit-test often returns an internal hosting subview, not a real `NSControl`.
- When hit-test returns `self`, `WindowDragNSView.mouseDown` consumes the event and **never forwards it**, so the control never receives the click.
- This matches the report: **only scrubbing works** because the slider bridges to an `NSSlider` (an `NSControl`), so it gets through. Buttons/text inputs often do not.

**Likely outcome**
- Play/pause, step, lock, help, zoom reset, etc. are dead because their clicks are swallowed.

### 2) Keyboard shortcuts are bound to the main window only
**Evidence**
- Keyboard handler is installed in `ContentView.handleKeyboardShortcuts()` (main window view).
- Control bar now lives in a **separate child window** (`AppDelegate.createControlWindow`).

**Why this breaks shortcuts / field increments**
- Local key monitors in `ContentView` are not guaranteed to run for the child window focus.
- The text fields now live in the control window; arrow keys and modifiers can be intercepted or never reach the field editor.

**Likely outcome**
- Key-based zoom/frame stepping and numeric field incrementing do not fire.

### 3) Main window can become mouse‑ignoring (click‑through)
**Evidence**
- When `isLocked` is true, the main window sets `window.ignoresMouseEvents = true`.
  - `AppDelegate.swift`: `observeState()` lock handling.

**Why this breaks zoom/pan**
- If lock toggle is stuck (due to hit-test swallowing the lock button), the main window remains click‑through.
- That stops **scroll** and **pan** from ever reaching `VideoMouseView`.

**Likely outcome**
- Zoom/pan appear broken, even though the logic exists.

### 4) Pan is gated behind zoom > 1.0
**Evidence**
- `VideoMouseView.mouseDown/Dragged` require `zoomScale > 1.0`.
  - `VideoPlayerView.swift` lines ~123–131.

**Why this matters**
- If zoom never changes (due to lock or swallowed scroll), pan is never enabled.

### 5) Control bar drag area design conflicts with clickable UI
**Evidence**
- Dragging is implemented by wrapping the entire control bar in the drag view.
- The drag view assumes only “real” AppKit controls should be clickable.

**Why this matters**
- This is the core architectural conflict: drag vs. clickable controls.
- Current implementation prioritizes drag, which defeats most SwiftUI control hit‑testing.

## Secondary / Contributing Issues

### Scroll zoom direction / magnitude
- Scroll direction depends on `scrollingDeltaY` sign (trackpads can vary).
- The current logic is brittle, but this is **secondary** compared to events not firing at all.

### Control bar moved to child window changes focus behavior
- Focused window is now the control window; the main window may no longer be key.
- This can break keyboard shortcut routing and any responder-chain assumptions.

## Root Cause Summary
The primary issue is **event routing**, not the zoom/pan math.

1) **The drag wrapper (`WindowDragNSView.hitTest`) is swallowing input events** for most SwiftUI controls, so buttons and fields never receive clicks or focus.
2) **Keyboard shortcuts are attached to the main window**, but the UI now lives in a child window, so key events are not handled consistently.
3) If lock is ever toggled on, the **main window becomes click‑through**, preventing all scroll/pan events from reaching the video view.

These combined explain why the only reliable interaction is the scrubber slider (which is a native AppKit control and survives hit-testing).

## Recommendations (No code changes applied in this report)

### A) Fix control bar hit‑testing
Options:
1) Remove the custom `hitTest` override and implement dragging only when clicking on a dedicated background area.
2) Use a separate transparent drag layer **behind** the controls so it only receives clicks in empty space.
3) If dragging must be “everywhere”, explicitly whitelist SwiftUI subviews as interactive by checking for `NSHostingView` descendants and letting them receive hits.

### B) Relocate keyboard shortcut handling
- Move the local monitor to `AppDelegate` (or a shared monitor) so both main and control windows receive key events consistently.

### C) Ensure lock state visibility / recovery
- If lock state is stuck, add a clear visual indicator and an emergency toggle (e.g., global shortcut only).

### D) Re-evaluate the two‑window architecture
- If click‑through is required for the video but not controls, the two‑window approach is reasonable.
- But it must be paired with correct event routing and focus handling.

## Files Referenced
- `VideoOverlay/VideoOverlay/Views/ContentView.swift`
- `VideoOverlay/VideoOverlay/Views/ControlWindowView.swift`
- `VideoOverlay/VideoOverlay/Views/ControlBarView.swift`
- `VideoOverlay/VideoOverlay/Views/VideoPlayerView.swift`
- `VideoOverlay/VideoOverlay/App/AppDelegate.swift`

## Next Step (If you want fixes)
Tell me whether you want:
1) Dragging to work on **any empty space** in the control bar (controls remain clickable), or
2) Dragging to work **everywhere** (but then we’ll need a custom hit-test list of allowed controls).

Once you choose, I’ll implement a targeted fix and re‑verify zoom/pan + controls.
