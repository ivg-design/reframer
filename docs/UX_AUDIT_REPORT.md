# Video Overlay - Comprehensive UX Audit Report

## Executive Summary

Complete audit of the Swift implementation identifying **all UX issues** preventing the app from functioning as specified in FEATURES.md. The app compiles but is ~95% non-functional due to critical bugs in event handling, state management, and API usage.

**Input Paradigm**: Mouse + Mouse Buttons + Scroll Wheel + Keyboard (with Shift/Cmd/Opt/Ctrl modifiers)

---

## Table of Contents

1. [Critical Bugs (P0)](#critical-bugs-p0---app-breaking)
2. [Input Field Incrementation Bugs](#input-field-keyboard-incrementation-bugs)
3. [Scrubbing & Seeking Issues](#scrubbing--seeking-issues)
4. [Keyboard Shortcut Issues](#keyboard-shortcut-issues)
5. [Mouse & Scroll Wheel Issues](#mouse--scroll-wheel-issues)
6. [Lock Mode Issues](#lock-mode-issues)
7. [Window & UI Issues](#window--ui-issues)
8. [File Handling Issues](#file-handling-issues)
9. [State Management Issues](#state-management-issues)
10. [Proposed Fixes](#proposed-fixes)

---

## Critical Bugs (P0 - App Breaking)

### 1. Keyboard Shortcuts Capture Stale State

**Location**: `ContentView.swift:261-352`

**Problem**:
```swift
struct KeyboardShortcutsModifier: ViewModifier {
    @EnvironmentObject var videoState: VideoState  // Captured once

    func body(content: Content) -> some View {
        content.onAppear {
            KeyboardShortcutMonitor.shared.installIfNeeded { event in
                if handleKey(event) { return nil }  // 'self' is stale!
                return event
            }
        }
    }
}
```

**Why it fails**:
- `ViewModifier` is a **struct** (value type)
- Closure captures `self` at `onAppear` time
- SwiftUI recreates structs on every render
- Captured `videoState` becomes disconnected from actual state
- **ALL keyboard shortcuts fail after any state change**

**Fix**:
```swift
// Option 1: Use a class-based handler
final class KeyboardHandler: ObservableObject {
    var videoState: VideoState?

    func install() {
        KeyboardShortcutMonitor.shared.installIfNeeded { [weak self] event in
            guard let self, let state = self.videoState else { return event }
            // Use live state reference
        }
    }
}

// Option 2: Access state through AppDelegate singleton
func handleKey(_ event: NSEvent) -> Bool {
    guard let appDelegate = NSApp.delegate as? AppDelegate else { return false }
    let videoState = appDelegate.videoState  // Always current
    // ...
}
```

---

### 2. Drag & Drop Completely Broken

**Location**: `DropZoneView.swift:66-88`

**Problem**:
```swift
provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
    if let url = item as? URL {  // FAILS - Finder provides NSURL
        // ...
    } else if let data = item as? Data,
              let url = URL(dataRepresentation: data, relativeTo: nil) {  // WRONG API
        // ...
    }
}
```

**Why it fails**:
- `item as? URL` fails because Finder provides `NSURL`, not Swift `URL`
- `URL(dataRepresentation:relativeTo:)` expects bookmark data, not path data
- No handling of file promises or security-scoped URLs
- `error` parameter ignored

**Fix**:
```swift
private func handleDrop(providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first else { return false }

    // Use the correct API for file URLs
    if provider.canLoadObject(ofClass: URL.self) {
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            guard let url = url else {
                print("Drop error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            DispatchQueue.main.async {
                self.videoState.videoURL = url
                self.videoState.isVideoLoaded = true
            }
        }
        return true
    }
    return false
}
```

---

### 3. Empty Entitlements File

**Location**: `VideoOverlay/Resources/VideoOverlay.entitlements`

**Current content**:
```xml
<dict/>  <!-- EMPTY! -->
```

**Fix** - Add required entitlements:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <!-- OR if sandboxed: -->
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.security.files.downloads.read-only</key>
    <true/>
</dict>
</plist>
```

---

## Input Field Keyboard Incrementation Bugs

### 4. Modified Arrow Keys Not Intercepted

**Location**: `NumericInputField.swift:75-90`

**Problem**:
```swift
func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.moveUp(_:)):      // Only catches UNMODIFIED Up
        stepValue(direction: 1)
        return true
    case #selector(NSResponder.moveDown(_:)):    // Only catches UNMODIFIED Down
        stepValue(direction: -1)
        return true
    // ...
    }
}
```

**Why it fails**:
- `Shift+Up` triggers `moveUpAndModifySelection(_:)` (not `moveUp(_:)`)
- `Cmd+Up` triggers `moveToBeginningOfDocument(_:)` (not `moveUp(_:)`)
- Modified arrow keys are NOT caught by this handler
- They fall through to default text editing behavior

**The backup `handleKeyDown` doesn't help**:
```swift
// IncrementingTextField.keyDown is NOT called when field editor is active!
// Events go through NSTextView's responder chain instead
override func keyDown(with event: NSEvent) {
    if keyDownHandler?(event) == true { return }  // Never reached during editing
    super.keyDown(with: event)
}
```

**Fix**:
```swift
func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    // Unmodified
    case #selector(NSResponder.moveUp(_:)):
        stepValue(direction: 1)
        return true
    case #selector(NSResponder.moveDown(_:)):
        stepValue(direction: -1)
        return true

    // Shift+Arrow (text selection commands - intercept them!)
    case #selector(NSResponder.moveUpAndModifySelection(_:)):
        stepValue(direction: 1)  // Shift modifier detected in stepValue
        return true
    case #selector(NSResponder.moveDownAndModifySelection(_:)):
        stepValue(direction: -1)
        return true

    // Cmd+Arrow (document navigation commands - intercept them!)
    case #selector(NSResponder.moveToBeginningOfDocument(_:)),
         #selector(NSResponder.moveToBeginningOfParagraph(_:)):
        stepValue(direction: 1)  // Cmd modifier detected in stepValue
        return true
    case #selector(NSResponder.moveToEndOfDocument(_:)),
         #selector(NSResponder.moveToEndOfParagraph(_:)):
        stepValue(direction: -1)
        return true

    // Enter/Esc
    case #selector(NSResponder.insertNewline(_:)),
         #selector(NSResponder.cancelOperation(_:)):
        control.window?.makeFirstResponder(nil)
        FocusReturnManager.shared.returnFocusToPreviousApp()
        return true

    default:
        return false
    }
}
```

### 5. Cmd+Shift+Arrow Not Handled

Even with the above fix, `Cmd+Shift+Up/Down` triggers different selectors:
- `moveToBeginningOfDocumentAndModifySelection(_:)`

**Additional selectors to handle**:
```swift
case #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)):
    stepValue(direction: 1)
    return true
case #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)):
    stepValue(direction: -1)
    return true
```

### 6. Option+Arrow Not Considered

**FEATURES.md** mentions Ctrl modifier but code only handles Shift and Cmd:
```swift
private func stepForFlags(_ flags: NSEvent.ModifierFlags) -> Double {
    if flags.contains(.command), let cmdStep = parent.cmdStep {
        return cmdStep
    }
    if flags.contains(.shift) {
        return parent.shiftStep
    }
    return parent.step
    // NO .option or .control handling!
}
```

**Fix** - Add all modifier combinations per FEATURES.md requirements.

---

## Scrubbing & Seeking Issues

### 7. CRITICAL: Scrubbing Has Severe Lag

**Location**: `ControlBarView.swift:31-50` and `VideoPlayerView.swift:245-251`

**Problem Chain**:
1. Slider `set:` posts `.seekToTime` notification
2. ContentView receives and relays to `.seekToTimeInternal`
3. VideoPlayerView receives and calls `scrub(to:)`
4. `scrub()` uses **frame-accurate seeking** (slow!):

```swift
func scrub(to time: Double, videoState: VideoState) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player?.currentItem?.cancelPendingSeeks()
    player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)  // SLOW!
}
```

**Why it's slow**:
- `toleranceBefore: .zero, toleranceAfter: .zero` = frame-accurate = SLOW
- For inter-frame codecs (H.264, HEVC), this requires decoding from nearest keyframe
- Double notification hop adds latency
- No throttling of rapid seek requests

**Fix** - Use fast seeking during scrub, accurate on release:
```swift
// In VideoPlayerManager
func scrubFast(to time: Double) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player?.currentItem?.cancelPendingSeeks()
    // Use default tolerance for speed during scrubbing
    player?.seek(to: cmTime)
}

func scrubFinalize(to time: Double, videoState: VideoState) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    // Frame-accurate only on scrub END
    player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
        videoState.currentTime = time
        videoState.currentFrame = Int(time * videoState.frameRate)
    }
}

// In ControlBarView - differentiate scrub vs release
Slider(
    value: Binding(
        get: { isScrubbing ? scrubValue : videoState.currentTime },
        set: { newValue in
            scrubValue = newValue
            // FAST seek during drag
            NotificationCenter.default.post(name: .scrubFast, object: newValue)
        }
    ),
    in: 0...max(0.1, videoState.duration),
    onEditingChanged: { editing in
        isScrubbing = editing
        if !editing {
            // ACCURATE seek on release
            NotificationCenter.default.post(name: .scrubFinalize, object: scrubValue)
        }
    }
)
```

### 8. Double Notification Relay Adds Latency

**Current flow**:
```
ControlBarView → .seekToTime → ContentView → .seekToTimeInternal → VideoPlayerView
```

**Why it exists**: ContentView was probably meant to coordinate, but it just relays.

**Fix** - Direct communication:
```swift
// Option 1: Direct notification (remove relay)
// VideoPlayerView listens to .seekToTime directly

// Option 2: Use Combine publisher from VideoState
class VideoState: ObservableObject {
    let seekRequest = PassthroughSubject<Double, Never>()
}

// ControlBarView
videoState.seekRequest.send(newValue)

// VideoPlayerView
.onReceive(videoState.seekRequest) { time in
    playerManager.scrub(to: time)
}
```

---

## Keyboard Shortcut Issues

### 9. Global Shortcuts Require Permission (Silent Failure)

**Location**: `AppDelegate.swift:115-125`

```swift
globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { ... }
```

**Problem**:
- Requires "Input Monitoring" permission on macOS 10.15+
- No permission check
- No user prompt
- Fails silently if denied

**Fix**:
```swift
func setupGlobalShortcuts() {
    // Check permission first
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)

    if !trusted {
        // Permission dialog shown, shortcuts won't work until granted
        print("Accessibility permission required for global shortcuts")
    }

    globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { ... }
}
```

### 10. Local Shortcuts Lost After State Changes

(See Issue #1 - stale state capture)

### 11. Key Codes Are Magic Numbers

**Location**: `ContentView.swift:287-330`

```swift
case 31 where flags == .command:  // What key is 31?
case 49 where videoState.isVideoLoaded:  // What key is 49?
case 123:  // ???
```

**Problem**: Unmaintainable, error-prone.

**Fix** - Use named constants or `event.charactersIgnoringModifiers`:
```swift
extension NSEvent {
    var isSpaceKey: Bool { keyCode == 49 }
    var isLeftArrow: Bool { keyCode == 123 }
    var isRightArrow: Bool { keyCode == 124 }
    var isUpArrow: Bool { keyCode == 126 }
    var isDownArrow: Bool { keyCode == 125 }
    // etc.
}
```

---

## Mouse & Scroll Wheel Issues

### 12. Scroll Wheel Frame Step Threshold Too High

**Location**: `VideoPlayerView.swift:169-173`

```swift
if delta > 0.5 {
    NotificationCenter.default.post(name: .frameStepBackward, object: 1)
} else if delta < -0.5 {
    NotificationCenter.default.post(name: .frameStepForward, object: 1)
}
```

**Problem**: Mouse scroll wheels often produce smaller deltas per tick.

**Fix**:
```swift
// For discrete scroll wheels, any non-zero delta should step
if !event.hasPreciseScrollingDeltas {
    // Discrete mouse wheel - step on any tick
    if delta > 0 {
        NotificationCenter.default.post(name: .frameStepBackward, object: 1)
    } else if delta < 0 {
        NotificationCenter.default.post(name: .frameStepForward, object: 1)
    }
} else {
    // Trackpad - accumulate (if you want trackpad support later)
    // ...
}
```

### 13. Scroll Zoom Direction May Be Inverted

**Current**:
```swift
let direction = delta < 0 ? 1.0 : -1.0
```

Verify this matches user expectation: scroll up = zoom in or scroll up = zoom out?

### 14. Pan Restricted to Zoom > 100%

**Location**: `VideoPlayerView.swift:124`

```swift
guard ... videoState.zoomScale > 1.0 else { return }
```

**Issue**: Users can't reposition video at 100% zoom. May be intentional but should be documented or configurable.

---

## Lock Mode Issues

### 15. Lock Mode Too Aggressive

**Location**: `AppDelegate.swift:81-86`

```swift
if isLocked {
    window.ignoresMouseEvents = true  // ALL mouse events blocked
}
```

**Per FEATURES.md**, when locked:
- ✓ Video area should be click-through
- ✓ Controls should remain interactive (separate window handles this)
- ✓ Zoom/Pan/Window movement LOCKED - but scroll wheel IS a mouse event!

**Current behavior blocks**:
- Scroll wheel (can't step frames in lock mode) - **CORRECT per spec**
- All clicks on main window - **CORRECT**

**This appears correct** per FEATURES.md: "Scroll wheel - Frame step forward/back - **disabled in lock mode**"

### 16. Lock Visual Indicator Uses Accent Color

**Location**: `OverlayViews.swift:20`

```swift
.background(Color.accentColor.opacity(0.9))
```

**Issue**: FEATURES.md says "Visual indicator when locked (lock icon change, highlight)". Current implementation is fine but verify accent color is visible against video content.

---

## Window & UI Issues

### 17. Control Window Height Too Small

**Location**: `AppDelegate.swift:19`

```swift
private let controlWindowHeight: CGFloat = 64
```

**Problem**: ControlBarView with all controls + padding + material effects exceeds 64pt:
- Buttons: 24pt
- Padding: 8pt × 2 = 16pt
- Total minimum: ~48pt + materials, shadows, dividers

**Symptoms**:
- Controls visually clipped
- Click targets extend outside window (unclickable)
- Shadow/blur cut off

**Fix**:
```swift
private let controlWindowHeight: CGFloat = 80  // Or measure dynamically
```

### 18. onChange Syntax Deprecated (macOS 14+)

**Location**: Multiple files

```swift
.onChange(of: videoState.currentFrame) { frameText = "\($0)" }  // Old syntax
```

**Fix for macOS 14+**:
```swift
.onChange(of: videoState.currentFrame) { oldValue, newValue in
    frameText = "\(newValue)"
}
```

### 19. No Dark Mode Enforcement

**FEATURES.md**: "DARK MODE FIRST"

**Fix**:
```swift
// In VideoOverlayApp.swift or AppDelegate
init() {
    NSApp.appearance = NSAppearance(named: .darkAqua)
}
```

---

## File Handling Issues

### 20. No Video Load Error UI

**Location**: `VideoPlayerView.swift:223-225`

```swift
} catch {
    print("Error: \(error)")  // Silent!
}
```

**Fix**: Show alert or error state:
```swift
} catch {
    await MainActor.run {
        videoState.loadError = error.localizedDescription
        videoState.isVideoLoaded = false
    }
}
```

### 21. Open Panel May Block Main Thread

**Location**: `ContentView.swift:64-75`

```swift
if panel.runModal() == .OK, let url = panel.url {
```

`runModal()` blocks the main thread. For better UX:
```swift
panel.begin { response in
    if response == .OK, let url = panel.url {
        DispatchQueue.main.async {
            videoState.videoURL = url
            videoState.isVideoLoaded = true
        }
    }
}
```

---

## State Management Issues

### 22. Over-Reliance on NotificationCenter

**Current notifications**:
- `.openVideo`
- `.toggleLock`
- `.frameStepForward`
- `.frameStepBackward`
- `.seekToTime`
- `.seekToTimeInternal`
- `.seekToFrame`
- `.seekToFrameInternal`

**Problems**:
- Fire-and-forget (no confirmation)
- Type-unsafe (`object as?` casts)
- Hard to debug
- Notifications lost if receiver not subscribed

**Fix** - Use Combine directly:
```swift
class VideoState: ObservableObject {
    // Replace notifications with subjects
    let seekRequest = PassthroughSubject<SeekRequest, Never>()
    let frameStepRequest = PassthroughSubject<Int, Never>()

    enum SeekRequest {
        case toTime(Double, accurate: Bool)
        case toFrame(Int)
    }
}
```

### 23. No Preference Persistence

Settings reset on every launch:
- Volume (always muted)
- Window position
- Always-on-top state
- Opacity

**Fix**: Use `UserDefaults` or `@AppStorage`:
```swift
@AppStorage("isAlwaysOnTop") var isAlwaysOnTop = true
@AppStorage("lastVolume") var volume: Float = 0.0
```

---

## Complete Fix Priority List

### Phase 1 - Make It Work (Critical)

| # | Issue | Fix Complexity |
|---|-------|----------------|
| 1 | Keyboard shortcuts stale state | Medium - refactor to class-based handler |
| 2 | Drag & drop broken | Easy - use correct `loadObject` API |
| 3 | Empty entitlements | Easy - add entitlements |
| 4-6 | Input field arrow keys with modifiers | Medium - add all command selectors |
| 7-8 | Scrubbing lag | Medium - fast/accurate seek split |
| 17 | Control window height | Easy - increase to 80pt |

### Phase 2 - Make It Reliable

| # | Issue | Fix Complexity |
|---|-------|----------------|
| 9 | Global shortcuts permission | Easy - add AXIsProcessTrusted |
| 12 | Scroll threshold | Easy - adjust threshold |
| 18 | onChange syntax | Easy - update syntax |
| 20 | No error UI | Easy - add error state |
| 22 | NotificationCenter overuse | Medium - migrate to Combine |

### Phase 3 - Polish

| # | Issue | Fix Complexity |
|---|-------|----------------|
| 11 | Magic key codes | Easy - add constants |
| 19 | Dark mode | Easy - set appearance |
| 21 | Modal blocking | Easy - use async panel |
| 23 | Preference persistence | Easy - add UserDefaults |

---

## Summary

**Total Issues Found**: 23

| Category | Count |
|----------|-------|
| Critical (P0) | 8 |
| Input Handling | 6 |
| Seeking/Scrubbing | 2 |
| Window/UI | 3 |
| File Handling | 2 |
| State Management | 2 |

**Root Causes**:
1. **Value type capture in closures** - ViewModifier struct captured instead of reference
2. **Wrong API usage** - NSItemProvider, onChange syntax
3. **Missing permission handling** - Accessibility/Input Monitoring
4. **Performance assumption** - Frame-accurate seeking during scrub
5. **Incomplete command handling** - Only unmodified arrow keys caught

---

*Audit completed: January 31, 2026*
*Input Paradigm: Mouse + Scroll Wheel + Keyboard (Shift/Cmd/Opt/Ctrl)*
