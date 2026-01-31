# VideoOverlay — Master Implementation Plan

**Date**: 2026-01-31
**Status**: Verified Implementation Plan (Revision 6)
**Current Deployment Target**: macOS 13.0 (Ventura) — **must update to 15.0 (Sequoia) as Phase 0**
**Target Platform**: macOS 26 (Tahoe) with macOS 15 (Sequoia) fallback
**Current Sandbox Setting**: `ENABLE_APP_SANDBOX = YES` — must use sandbox-compatible entitlements
**Input Paradigm**: Mouse + Scroll Wheel + Keyboard (Shift/Cmd modifiers only)

---

## Issue Status

| # | Issue | Location | Status | Root Cause |
|---|-------|----------|--------|------------|
| 1 | Drag & drop API wrong | `DropZoneView.swift:71-84` | **CONFIRMED** | Uses `loadItem` with wrong type cast |
| 2 | Entitlements incomplete | `VideoOverlay.entitlements` | **CONFIRMED** | Empty `<dict/>` with sandbox enabled |
| 3 | Keyboard monitor not app-scoped | `ContentView.swift:342-352` | **SUSPECTED** | `installIfNeeded` installs once; may be window-scope issue |
| 4 | Hit-testing swallows SwiftUI controls | `ContentView.swift:158-170` | **CONFIRMED** | Only checks for NSControl/NSTextView |
| 5 | Input field modifiers not caught | `NumericInputField.swift:75-90` | **CONFIRMED** | Missing Shift/Cmd arrow selectors |
| 6 | Global shortcuts permission | `AppDelegate.swift:114-125` | **CONFIRMED** | No permission check or user guidance |
| 7 | Control window height 64pt | `AppDelegate.swift:19` | **CONFIRMED** | May clip controls |

**Note on Issue #3**: `VideoState` is a class (reference type), so captured references don't "go stale." The actual issue is likely:
- Monitor installed from view lifecycle (may not cover child window)
- `installIfNeeded` captures first handler and ignores subsequent calls
- Requires instrumentation to confirm root cause

---

## Design Decisions (Locked In)

| Decision | Value | Source |
|----------|-------|--------|
| Scroll up direction | Zoom OUT | User confirmed via AskUserQuestion (this conversation): "Scroll up = Zoom OUT" |
| Extra modifiers in inputs | None | FEATURES.md (Shift/Cmd only) |
| Shift required for zoom scroll | Yes | FEATURES.md: "Shift+Scroll - Zoom in/out" |
| Cmd+Scroll alone | Does nothing | FEATURES.md specifies Cmd+**Shift**+Scroll only |
| Pan at zoom == 100% | Disabled | Pan only allowed when zoomScale > 1.0 (per current code) |

---

## Phase 0: Prerequisites

### 0.1 Update Deployment Target

**Location**: Xcode project settings (`project.pbxproj`)

**Current**: `MACOSX_DEPLOYMENT_TARGET = 13.0` (Ventura)
**Required**: `MACOSX_DEPLOYMENT_TARGET = 15.0` (Sequoia)

This is required because:
- Tahoe (26) features use `#available(macOS 26, *)` with Sequoia (15) fallback
- Some SwiftUI APIs used may require 15+
- Ensures consistent behavior across target platforms

**Action** — Update BOTH configurations:
1. In Xcode: Project → Build Settings → Deployment → macOS Deployment Target
2. Set to `15.0` for **both Debug AND Release** configurations
3. Verify in `project.pbxproj` that BOTH lines show `MACOSX_DEPLOYMENT_TARGET = 15.0`:
   - Line ~279 (Debug)
   - Line ~338 (Release)

---

## Phase 1: Event Routing (Critical)

### 1.1 Fix Hit-Testing for SwiftUI Controls

**Location**: `ContentView.swift:153-188` (WindowDragView and WindowDragNSView)

**Problem**: Current hit-test only returns `hitView` if it's an `NSControl` or `NSTextView`. SwiftUI controls are NOT `NSControl` subclasses—they're hosted inside `NSHostingView`. The current code intercepts them for drag.

**Why my previous fix was wrong**: `super.hitTest(point)` returns the **deepest** view containing the point. When NSHostingView hosts SwiftUI content, even "empty" areas hit internal SwiftUI views (not `self`), so checking `hitView === self` would NEVER allow drag.

**Correct Fix** — Use a **layered architecture** instead of hit-test manipulation:

```swift
// ARCHITECTURE CHANGE:
// Instead of wrapping SwiftUI in a drag view that manipulates hit-testing,
// place a transparent drag layer BEHIND the SwiftUI content.

// ControlWindowView.swift (or wherever the control bar is set up)
struct ControlWindowView: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        ZStack {
            // LAYER 1: Drag background (behind everything)
            // This receives hits only where SwiftUI content doesn't cover
            WindowDragBackground(videoState: videoState)

            // LAYER 2: SwiftUI controls (on top)
            // These naturally receive their own hits
            ControlBarView()
        }
    }
}

// Drag background that only handles mouse events for window movement
struct WindowDragBackground: NSViewRepresentable {
    let videoState: VideoState

    func makeNSView(context: Context) -> DragBackgroundNSView {
        let view = DragBackgroundNSView()
        view.videoState = videoState
        return view
    }

    func updateNSView(_ nsView: DragBackgroundNSView, context: Context) {
        nsView.videoState = videoState
    }
}

class DragBackgroundNSView: NSView {
    weak var videoState: VideoState?
    private var dragStart: NSPoint = .zero
    private var windowStart: NSPoint = .zero

    // This view naturally receives hits where SwiftUI doesn't cover
    // No hit-test override needed!

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard videoState?.isLocked != true else {
            super.mouseDown(with: event)
            return
        }
        dragStart = NSEvent.mouseLocation
        windowStart = (window?.parent ?? window)?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard videoState?.isLocked != true else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y
        (window?.parent ?? window)?.setFrameOrigin(NSPoint(x: windowStart.x + dx, y: windowStart.y + dy))
    }
}
```

**Key insight**: ZStack layering means SwiftUI controls sit ON TOP of the drag background. SwiftUI's built-in hit-testing naturally routes clicks to the topmost view that wants them. Buttons/sliders/inputs receive their clicks; empty space falls through to the drag background.

**Critical: ControlBarView background must be non-hittable**

**Location**: `VideoOverlay/VideoOverlay/Views/ControlBarView.swift`

The current `ControlBarView` applies a background material (`.ultraThinMaterial`) to the entire HStack. This makes the ENTIRE bar hit-testable, blocking the drag layer underneath.

**Fix** — Make the visual background non-hittable:

```swift
// ControlBarView.swift
var body: some View {
    HStack(spacing: 12) {
        // ... controls ...
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background {
        // Visual background - NOT hittable
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .allowsHitTesting(false)  // CRITICAL: Let clicks pass through to drag layer
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
}
```

**Why this works**: With `.allowsHitTesting(false)` on the background, only the actual controls (buttons, sliders, inputs) receive hits. Clicks between controls pass through the background to the drag layer.

**What to remove**: Delete the existing `WindowDragView` and `WindowDragNSView` wrapper approach that manipulates hit-testing.

**Handle behavior**: The existing `WindowDragHandle` (bottom-right corner) is a separate NSView-based component. It should remain unchanged and NOT be covered by the drag background layer. Ensure the ZStack order keeps the handle interactive:
```swift
ZStack {
    WindowDragBackground(videoState: videoState)  // Bottom layer
    ControlBarView()                               // Controls on top
    // WindowDragHandle is in ContentView, not control bar - unaffected
}
```

**Tests**:
- `CB-001`: All buttons/sliders/inputs respond to clicks
- `CB-002`: Drag on empty toolbar space (between controls) moves window

---

### 1.2 Move Keyboard Monitor to AppDelegate

**Location**: `ContentView.swift:261-352` → `AppDelegate.swift`

**Validation before fix** — Test keyboard events from control window:
1. Run app, load a video
2. Click on a control in the control bar (e.g., the timeline slider) to give it focus
3. Press Space (play/pause) or arrow keys (frame step)
4. **If shortcuts don't work when control window has focus**, the issue is window scope
5. **If shortcuts work initially but fail after state changes**, the issue is the `installIfNeeded` pattern
6. Add temporary `print()` in `handleKey()` to confirm whether events are received

**Suspected issues** (Issue #3 is SUSPECTED, not confirmed):
- Monitor installed from view lifecycle (may not cover child window)
- `installIfNeeded` captures first handler and ignores subsequent calls
- Note: `VideoState` is a reference type, so captured references don't "go stale"

**Fix** — Install monitor in AppDelegate at app launch:

```swift
// AppDelegate.swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var videoState = VideoState()
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow()
        FocusReturnManager.shared.startTracking()
        setupKeyboardMonitoring()  // Install ONCE at app launch
        ensureInstalledInApplications()
        observeState()
    }

    private func setupKeyboardMonitoring() {
        // Local monitor — handles events when app is active (both windows)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKey(event) ? nil : event
        }

        // Global monitor — handles events when app is inactive
        // NOTE: Requires Input Monitoring permission (no API to check - see 1.3)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKey(event)
        }
    }

    private func handleLocalKey(_ event: NSEvent) -> Bool {
        // Check if text field has focus — let it handle events
        let responder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder
        if responder is NSTextView {
            // Only intercept Escape/Enter to defocus
            if event.keyCode == 53 || event.keyCode == 36 {
                NSApp.keyWindow?.makeFirstResponder(nil)
                FocusReturnManager.shared.returnFocusToPreviousApp()
                return true
            }
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift)

        switch event.keyCode {
        case 49 where videoState.isVideoLoaded && flags.isEmpty:  // Space
            videoState.isPlaying.toggle()
            return true
        case 123 where videoState.isVideoLoaded:  // Left arrow
            NotificationCenter.default.post(name: .frameStepBackward, object: shift ? 10 : 1)
            return true
        case 124 where videoState.isVideoLoaded:  // Right arrow
            NotificationCenter.default.post(name: .frameStepForward, object: shift ? 10 : 1)
            return true
        case 126 where videoState.isVideoLoaded && !videoState.isLocked:  // Up arrow
            videoState.adjustZoom(byPercent: shift ? 10 : 5)
            return true
        case 125 where videoState.isVideoLoaded && !videoState.isLocked:  // Down arrow
            videoState.adjustZoom(byPercent: shift ? -10 : -5)
            return true
        case 24 where videoState.isVideoLoaded && !videoState.isLocked:  // + key
            videoState.adjustZoom(byPercent: 5)
            return true
        case 27 where videoState.isVideoLoaded && !videoState.isLocked:  // - key
            videoState.adjustZoom(byPercent: -5)
            return true
        case 29 where videoState.isVideoLoaded && !videoState.isLocked && flags.isEmpty:  // 0 key
            videoState.zoomScale = 1.0
            return true
        case 15 where flags.isEmpty && !videoState.isLocked:  // R key
            videoState.resetView()
            return true
        case 37 where flags.isEmpty:  // L key
            videoState.isLocked.toggle()
            return true
        case 4 where flags.isEmpty:  // H key
            videoState.showHelp.toggle()
            return true
        case 44 where shift:  // ? key (Shift+/)
            videoState.showHelp.toggle()
            return true
        case 31 where flags == .command:  // Cmd+O
            NotificationCenter.default.post(name: .openVideo, object: nil)
            return true
        case 53 where videoState.showHelp:  // Escape
            videoState.showHelp = false
            return true
        default:
            return false
        }
    }
}
```

**Remove from ContentView.swift**:
- Delete `KeyboardShortcutsModifier` struct (lines 261-334)
- Delete `KeyboardShortcutMonitor` class (lines 342-352)
- Remove `.handleKeyboardShortcuts()` modifier from ContentView

---

### 1.3 Global Shortcut Permission Handling

**Problem**: `NSEvent.addGlobalMonitorForEvents` requires **Input Monitoring** permission (Privacy & Security > Input Monitoring), NOT Accessibility permission.

**Important**: There is **no API** to programmatically check if Input Monitoring permission is granted. `AXIsProcessTrustedWithOptions` checks Accessibility permission, which is a DIFFERENT permission.

**Do NOT use** `AXIsProcessTrustedWithOptions` — that's for Accessibility, not Input Monitoring.

**Correct approach** — Two-part UX:

**Part A: One-time alert on first launch** (more visible)
```swift
// AppDelegate.swift - in applicationDidFinishLaunching
private func showGlobalShortcutPermissionAlert() {
    // Only show once
    guard !UserDefaults.standard.bool(forKey: "hasShownInputMonitoringAlert") else { return }
    UserDefaults.standard.set(true, forKey: "hasShownInputMonitoringAlert")

    let alert = NSAlert()
    alert.messageText = "Enable Global Shortcuts"
    alert.informativeText = "To use global shortcuts (Cmd+Shift+L to toggle lock) when other apps are focused, please enable Input Monitoring for VideoOverlay in System Settings."
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")

    if alert.runModal() == .alertFirstButtonReturn {
        // Open Input Monitoring settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Part B: Help UI reference** (for users who skipped the alert)
```swift
// In HelpModalView:
Text("Global shortcuts require Input Monitoring permission.")
    .font(.caption)
    .foregroundStyle(.secondary)

Text("System Settings > Privacy & Security > Input Monitoring")
    .font(.caption)
    .foregroundStyle(.secondary)
```

---

## Phase 2: Input Field Modifier Handling

### 2.1 Catch All Arrow Key Command Selectors

**Location**: `NumericInputField.swift:75-90`

**Fix** — Add Shift and Cmd arrow selectors:

```swift
func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    // UNMODIFIED arrows
    case #selector(NSResponder.moveUp(_:)):
        stepValue(direction: 1, modifiers: [])
        return true
    case #selector(NSResponder.moveDown(_:)):
        stepValue(direction: -1, modifiers: [])
        return true

    // SHIFT+arrows
    case #selector(NSResponder.moveUpAndModifySelection(_:)):
        stepValue(direction: 1, modifiers: [.shift])
        return true
    case #selector(NSResponder.moveDownAndModifySelection(_:)):
        stepValue(direction: -1, modifiers: [.shift])
        return true

    // CMD+arrows
    case #selector(NSResponder.moveToBeginningOfDocument(_:)),
         #selector(NSResponder.moveToBeginningOfParagraph(_:)):
        stepValue(direction: 1, modifiers: [.command])
        return true
    case #selector(NSResponder.moveToEndOfDocument(_:)),
         #selector(NSResponder.moveToEndOfParagraph(_:)):
        stepValue(direction: -1, modifiers: [.command])
        return true

    // ENTER/ESC — defocus
    case #selector(NSResponder.insertNewline(_:)),
         #selector(NSResponder.cancelOperation(_:)):
        control.window?.makeFirstResponder(nil)
        FocusReturnManager.shared.returnFocusToPreviousApp()
        return true

    default:
        return false
    }
}

private func stepValue(direction: Int, modifiers: NSEvent.ModifierFlags) {
    let step: Double
    if modifiers.contains(.command) {
        step = parent.cmdStep ?? parent.step
    } else if modifiers.contains(.shift) {
        step = parent.shiftStep
    } else {
        step = parent.step
    }

    let current = Double(parent.text) ?? parent.min
    let newValue = clamp(current + (step * Double(direction)))
    let formatted = formatValue(newValue)
    parent.text = formatted
    textField?.stringValue = formatted
    applyValue(from: formatted)
}
```

---

## Phase 3: Drag & Drop Fix

### 3.1 Use Correct NSItemProvider API

**Location**: `DropZoneView.swift:66-88`

**Validation before fix**: Test current drag & drop behavior:
1. Run app, drag a video file from Finder onto the drop zone
2. Check Console.app for "Drop error" messages
3. If drop silently fails (no video loads, no error), the `loadItem` API issue is confirmed

**Current code problem**:
- `item as? URL` fails because Finder provides `NSURL`, not Swift `URL`
- `URL(dataRepresentation:relativeTo:)` expects bookmark data, not path bytes

```swift
private func handleDrop(providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }

    if provider.canLoadObject(ofClass: URL.self) {
        _ = provider.loadObject(ofClass: URL.self) { [weak self] url, error in
            guard let url = url, error == nil else {
                print("Drop error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            guard VideoFormats.supportedTypes.contains(where: {
                UTType(filenameExtension: url.pathExtension)?.conforms(to: $0) == true
            }) else { return }

            DispatchQueue.main.async {
                self?.videoState.videoURL = url
                self?.videoState.isVideoLoaded = true
            }
        }
        return true
    }
    return false
}
```

---

## Phase 4: Entitlements

### 4.1 Populate Entitlements for Sandboxed App

**Location**: `VideoOverlay/Resources/VideoOverlay.entitlements`

**Current build setting**: `ENABLE_APP_SANDBOX = YES`

**Required entitlements** (sandbox-compatible):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.files.downloads.read-only</key>
    <true/>
</dict>
</plist>
```

**Note**: This keeps sandbox ENABLED (matching the build setting). User-selected files (via Open dialog or drag-drop) will be accessible. If you need to disable sandbox, you must ALSO change `ENABLE_APP_SANDBOX = NO` in build settings.

---

## Phase 5: Scroll Wheel Semantics

### 5.1 Scroll Behavior per FEATURES.md

**Requirements**:
- Scroll alone (no modifiers) = Frame step
- **Shift+Scroll** = Zoom 5% increments
- **Cmd+Shift+Scroll** = Zoom 0.1% increments
- **Cmd+Scroll alone** = Does nothing (not in spec)
- Scroll UP = Zoom OUT (user confirmed)

```swift
override func scrollWheel(with event: NSEvent) {
    guard !videoState.isLocked else { return }

    let delta = event.scrollingDeltaY
    guard delta != 0 else { return }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let hasShift = flags.contains(.shift)
    let hasCmd = flags.contains(.command)

    // ZOOM: Requires Shift (with or without Cmd)
    if hasShift {
        // Cmd+Shift = 0.1%, Shift alone = 5%
        let zoomIncrement: Double = hasCmd ? 0.001 : 0.05

        // Scroll UP (positive delta) = zoom OUT (user confirmed)
        let direction = delta > 0 ? -1.0 : 1.0
        videoState.zoomScale += direction * zoomIncrement
        videoState.zoomScale = max(0.1, min(10.0, videoState.zoomScale))

    // FRAME STEP: No modifiers only
    } else if flags.isEmpty {
        let isDiscreteWheel = !event.hasPreciseScrollingDeltas

        if isDiscreteWheel {
            if delta > 0 {
                NotificationCenter.default.post(name: .frameStepBackward, object: 1)
            } else {
                NotificationCenter.default.post(name: .frameStepForward, object: 1)
            }
        } else {
            if delta > 0.5 {
                NotificationCenter.default.post(name: .frameStepBackward, object: 1)
            } else if delta < -0.5 {
                NotificationCenter.default.post(name: .frameStepForward, object: 1)
            }
        }
    }
    // Cmd alone (without Shift): explicitly does nothing
}
```

---

## Phase 6: Scrubbing Performance

### 6.1 Fast Seek During Drag, Accurate on Release

```swift
func scrubFast(to time: Double) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player?.currentItem?.cancelPendingSeeks()
    player?.seek(to: cmTime)  // Default tolerance = fast
}

func scrubFinalize(to time: Double) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
}
```

---

## Phase 7: Window & UI

### 7.1 Increase Control Window Height

**Location**: `AppDelegate.swift:19`

```swift
private let controlWindowHeight: CGFloat = 80  // Was 64
```

### 7.2 Liquid Glass with Fallback

```swift
.background {
    if #available(macOS 26, *) {
        RoundedRectangle(cornerRadius: 12)
            .fill(.regularMaterial)
            .glassEffect(.regular)
    } else {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
    }
}
```

### 7.3 Dark Mode Enforcement

```swift
// AppDelegate.applicationDidFinishLaunching
NSApp.appearance = NSAppearance(named: .darkAqua)
```

---

## Implementation Checklist

### Phase 0: Prerequisites
- [ ] 0.1 Update MACOSX_DEPLOYMENT_TARGET to 15.0 in Xcode (BOTH Debug AND Release)

### Phase 1: Event Routing
- [ ] 1.1 Replace WindowDragView wrapper with ZStack layered architecture
- [ ] 1.1b Create DragBackgroundNSView (no hit-test override)
- [ ] 1.1c Add `.allowsHitTesting(false)` to ControlBarView background material
- [ ] 1.2 Validate keyboard monitor issue (test from control window, add debug print)
- [ ] 1.2a Move keyboard monitor to AppDelegate.applicationDidFinishLaunching
- [ ] 1.2b Remove KeyboardShortcutsModifier from ContentView
- [ ] 1.2c Remove KeyboardShortcutMonitor class from ContentView
- [ ] 1.2d Verify fix resolves the validated issue
- [ ] 1.3a Add one-time Input Monitoring permission alert on first launch
- [ ] 1.3b Add Input Monitoring guidance to Help UI

### Phase 2: Input Fields
- [ ] 2.1 Add Shift/Cmd arrow selectors to NumericInputField

### Phase 3: Drag & Drop
- [ ] 3.0 Validate current drag & drop failure (test with Finder drag)
- [ ] 3.1 Use `loadObject(ofClass: URL.self)` API

### Phase 4: Entitlements
- [ ] 4.1 Add sandbox entitlements: `files.user-selected.read-only`, `files.downloads.read-only`

### Phase 5: Scroll Semantics
- [ ] 5.1 Gate zoom on `hasShift` (Cmd alone does nothing)
- [ ] 5.2 Scroll up = zoom OUT

### Phase 6: Scrubbing
- [ ] 6.1 Fast seek during drag, accurate on release

### Phase 7: Window & UI
- [ ] 7.1 Increase control window height to 80pt
- [ ] 7.2 Add Liquid Glass fallback
- [ ] 7.3 Enforce dark mode
- [ ] 7.4 Update MACOSX_DEPLOYMENT_TARGET in Xcode if targeting macOS 15+ features

---

## Test Coverage

| ID | Test | Pass Criteria |
|----|------|---------------|
| CB-001 | Controls clickable with drag enabled | Buttons/sliders/inputs respond |
| CB-002 | Drag on empty toolbar space | Window moves |
| K-007 | Shortcuts after state changes | Shortcuts work reliably |
| IM-001 | Frame input Shift+Arrow | Steps 10 frames |
| IM-002 | Zoom input Cmd+Arrow | Steps 0.1% |
| IM-003 | Zoom input Shift+Arrow | Steps 10% |
| IM-004 | Opacity input Shift+Arrow | Steps 10% |
| SC-001 | Shift+scroll up | Zoom decreases (OUT) |
| SC-002 | Shift+scroll down | Zoom increases (IN) |
| SC-003 | Cmd+scroll alone | Nothing happens |
| SC-004 | Scroll without modifiers | Frame steps |
| F-102 | Drag from Finder | Video loads |
| V-003 | Scrub during drag | Frame updates in real-time |

---

## Summary

**7 issues** addressed across **7 files**:

| File | Changes |
|------|---------|
| `project.pbxproj` | Update MACOSX_DEPLOYMENT_TARGET to 15.0 (Debug + Release) |
| `ContentView.swift` | Replace WindowDragView with layered ZStack; remove keyboard code |
| `ControlBarView.swift` | Add `.allowsHitTesting(false)` to background material |
| `AppDelegate.swift` | Add keyboard monitoring; permission alert; increase control height |
| `NumericInputField.swift` | Add Shift/Cmd command selectors |
| `DropZoneView.swift` | Use correct `loadObject` API |
| `VideoOverlay.entitlements` | Add sandbox file entitlements |
| `VideoPlayerView.swift` | Enforce Shift for zoom; scroll up = zoom out; fast scrub |

---

*Master Implementation Plan — Revision 6 — January 31, 2026*
