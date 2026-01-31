# UX Audit vs Reconciliation — Comparison & Missing UX Coverage

Date: 2026-01-31

## Purpose
This document compares **UX_AUDIT_REPORT.md** and **REPORT_RECONCILIATION.md**, reconciles differences, and identifies **missing UX issues**. It also evaluates whether **FEATURE_TESTS.md** covers all UX‑critical interactions (keyboard/mouse/scroll/modifiers).

Target platform: **macOS Tahoe (26)** with **Sequoia (15) compatibility**.

---

## High‑Level Comparison

### Areas where both reports agree
- **Event routing is the root cause** of “nothing works.”
  - Drag view hit‑testing swallows control interactions.
  - Keyboard shortcuts are mis‑scoped due to multi‑window architecture.
- **Lock mode can block all interactions** if the user can’t reach the lock toggle.
- **Two‑window architecture is valid** but must preserve control interactivity.

### UX Audit (UX_AUDIT_REPORT.md) unique findings
- **Keyboard shortcut handler captures stale state** due to `ViewModifier` closure capture.
- **Input field modifier increments are not handled** (Shift/Cmd/Shift+Cmd selectors).
- **Scrubbing performance issue** (frame‑accurate seek during drag).
- **Global shortcut permissions** (Input Monitoring/Accessibility) not requested.
- **Drag & drop may be broken** due to `NSItemProvider` API usage.
- **Scroll wheel threshold too high** (trackpad/mouse deltas may never trigger).
- **Control window height too small** causing clipped controls / hit areas.

### Reconciliation report (REPORT_RECONCILIATION.md) unique focus
- **Drag‑to‑move should be limited to empty toolbar space** + bottom‑right handle.
- **Move keyboard monitoring into AppDelegate** for multi‑window correctness.
- **Tahoe vs Sequoia styling path** (glassEffect vs material fallback).

---

## Missing UX Issues (Not fully captured across both reports)

### 1) **Input modifiers inside fields**
- UX audit notes that Shift/Cmd/Shift+Cmd arrow selectors are not intercepted.
- Reconciliation report doesn’t explicitly address **modifier handling semantics** for inputs.
- **Impact**: Zoom/Opacity/Frame fields don’t honor modifier increments (1 / 10 / 0.1).

### 2) **Global shortcut permission UX**
- UX audit covers the technical requirement; reconciliation does not.
- **Impact**: Global shortcuts silently fail unless permissions are granted.
- **UX requirement**: Display an explicit permission prompt path or help link.

### 3) **Scrubbing UX quality**
- UX audit highlights lag due to frame‑accurate seek during drag.
- Reconciliation report does not cover this.
- **Impact**: The scrubber feels unresponsive even if “working.”

### 4) **Scroll zoom direction + delta scaling**
- UX audit flags direction mismatch and threshold issues.
- Reconciliation report mentions routing only, not direction/magnitude semantics.

### 5) **Control window height / clipping**
- UX audit notes the toolbar might be clipped and hit targets fall outside window bounds.
- Reconciliation report doesn’t mention control window sizing.

### 6) **Drag & drop correctness**
- UX audit warns that the `loadItem` API usage may fail.
- Reconciliation report says drop works (conflict).
- **Needs verification** with Finder drag‑drop; should be resolved.

---

## Reconciled UX Priority List (Ordered)
1) **Fix drag hit‑testing** so controls are always clickable and drag works only on empty toolbar space + handle.
2) **Move keyboard shortcut monitor to app‑level** and avoid stale `ViewModifier` capture.
3) **Fix numeric input modifier handling** (Shift/Cmd/Shift+Cmd in field editor selectors).
4) **Verify drag & drop implementation** using correct `NSItemProvider.loadObject` API if needed.
5) **Improve scrubbing UX**: fast seek while dragging, accurate seek on release.
6) **Normalize scroll semantics** (direction, discrete wheel thresholds, trackpad scaling).
7) **Adjust control window height** to avoid clipped hit areas.
8) **Add permission UX** for global shortcuts (Input Monitoring/Accessibility).

---

## Feature Test Coverage vs UX Requirements

### What FEATURE_TESTS.md already covers
- Most **keyboard shortcuts** (local and global).
- All **mouse/scroll gestures** in general terms.
- Drag to move and resize windows.
- Lock mode behavior.

### What is missing or under‑specified in FEATURE_TESTS.md
1) **Input modifiers inside fields**
   - Needs explicit tests for Shift/Cmd/Shift+Cmd arrows in zoom/opacity/frame inputs.

2) **Field editor routing**
   - A test to ensure the field receives focus and keyboard events even with drag view present.

3) **Scroll semantics**
   - Tests should specify expected zoom direction (scroll up = zoom in) and delta behavior for mouse vs trackpad.

4) **Scrub performance**
   - Should assert continuous frame updates during drag (fast seek), not just on release.

5) **Global shortcut permission UX**
   - Test should confirm a prompt/help path is shown if permission missing.

6) **Drag & drop success path**
   - Must confirm Finder drag‑drop works using real file URLs.

7) **Control bar hit targets**
   - Test should assert controls remain clickable even when toolbar drag is enabled.

---

## Recommendation: Update Test Plan
Add explicit UX tests to `FEATURE_TESTS.md` for:
- Modifier increments within input fields (Shift/Cmd/Shift+Cmd).
- Field focus retention vs toolbar drag (inputs remain reachable).
- Scroll direction and sensitivity (mouse wheel vs trackpad).
- Scrub responsiveness (continuous frame updates).
- Global shortcut permission UX.
- Drag & drop via Finder file URL.

---

## Bottom Line
The reconciliation report correctly identifies the **core event‑routing failures**, but it under‑represents **modifier‑specific UX behavior** and **scrubbing/scroll fidelity**. The UX audit adds those details but needs alignment with the Tahoe+Sequoia target.

**Action**: Merge both into a single UX‑focused implementation plan and update the test plan to validate modifier semantics and interaction quality explicitly.
