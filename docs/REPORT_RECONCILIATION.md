# VideoOverlay — Findings, Recommendations, and Reconciliation Plan

Date: 2026-01-31

## Scope
- Compare `IMPLEMENTATION_REPORT.md` vs current code behavior.
- Provide correct approach for **macOS Tahoe (26)** with **compatibility down to Sequoia (15)**.
- Define expected behavior: **drag-to-move works only on empty toolbar space + bottom-right handle**.

---

## Findings (What’s actually broken)

### 1) Control bar hit-testing swallows most controls
**Root cause**: The drag wrapper (`WindowDragNSView.hitTest`) returns `self` for most SwiftUI subviews, so clicks never reach buttons/text fields.
- Effect: Most controls appear dead (play/pause, lock, help, etc.)
- Reason: SwiftUI `Button` is not `NSControl`, so the hit-test treats it as “empty space” and intercepts.

### 2) Keyboard shortcuts bound to the wrong window
**Root cause**: Local key monitor is installed in `ContentView` (main window), but the control bar now lives in a **separate child window**.
- Effect: Arrow key increments and shortcuts don’t fire when focus is in the control bar.

### 3) Lock mode can permanently block input to the video window
**Root cause**: When locked, `mainWindow.ignoresMouseEvents = true`. If the lock toggle itself is unreachable (due to issue #1), it can trap the user in a click-through state.
- Effect: Zoom/pan/scroll do not work even though the code exists.

### 4) Implementation report doesn’t match the project target
**Root cause**: Report assumes macOS 26 only and `glassEffect`, but project is set to macOS 13. 
- Effect: Report suggests features that don’t compile or aren’t relevant to Sequoia.

---

## Recommendations (Correct approach for Tahoe + Sequoia)

### A) Drag behavior should use **empty toolbar space only**
Implement a drag-only background layer behind the control bar, and allow real controls to receive clicks. Two valid patterns:
1) **Background drag view**: Transparent NSView behind controls that only receives hits in empty space.
2) **Hit-test filter**: If hit view is inside a SwiftUI control, forward the hit; otherwise drag.

This aligns with your requirement:
- Drag to move works **only on empty toolbar space** + bottom-right handle.

### B) Unify keyboard event handling across windows
Move the local key monitor to `AppDelegate` (or a shared monitor) so it captures input from both main and control windows.

### C) Lock mode should never block the control bar
Keep the **main video window click-through**, but ensure the control bar window remains interactive and can always unlock.

### D) Target macOS Tahoe with Sequoia fallback
Use `glassEffect` on Tahoe (macOS 26) and fallback to `.ultraThinMaterial` on Sequoia (macOS 15). This should be an `if #available(macOS 26, *)` switch.

---

## Reconciliation: Report vs Correct Plan

### 1) Platform & Design System
- **Report**: Assumes macOS 26 only.
- **Correct**: Target macOS 26 with Sequoia compatibility.
- **Plan**: Wrap Liquid Glass styling in availability checks; keep current materials as fallback.

### 2) Input & Controls
- **Report**: Suggests everything is complete.
- **Correct**: Input handling is broken due to drag hit-testing and window focus.
- **Plan**:
  - Fix hit-testing so controls always receive clicks.
  - Move keyboard shortcut handling to app-level monitor.

### 3) Lock / Ghost Mode
- **Report**: Child window approach is valid.
- **Correct**: It’s valid only if control bar stays interactive.
- **Plan**:
  - Keep control bar in separate window.
  - Ensure it never becomes click-through.
  - Guarantee global shortcut toggles lock in all states.

### 4) Zoom/Pan
- **Report**: Says zoom/pan are implemented.
- **Correct**: Logic exists but events never reach it.
- **Plan**: Fix event routing; don’t change zoom math until routing is corrected.

---

## Proposed Implementation Plan (High-Level)
1) **Refactor drag hit-testing**
   - Only empty toolbar background drags the window.
   - Controls remain fully interactive.

2) **Move key event monitoring**
   - Install a single local monitor in `AppDelegate`.
   - Ensure it receives events from both windows.

3) **Lock mode resiliency**
   - Main window click-through only, control window always interactive.
   - Ensure global shortcut works even when locked.

4) **Tahoe/Sequoia UI path**
   - Tahoe: `glassEffect`.
   - Sequoia: `.ultraThinMaterial`.

---

## Outcome Expected After Reconciliation
- All controls respond consistently (buttons, inputs, shortcuts).
- Drag works **only** on empty toolbar space + handle.
- Lock mode never blocks access to controls.
- Zoom/pan work because events reach the video view.
- UI looks correct on Tahoe with graceful fallback on Sequoia.

---

## Next Steps
If you want, I’ll implement the reconciliation plan directly in the codebase.
