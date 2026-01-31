# Video Overlay - Swift/macOS Tahoe Implementation Report

## Executive Summary

This report analyzes the requirements from `FEATURES.md` and provides comprehensive guidance for implementing a 100% accurate native Swift/macOS application targeting **macOS Tahoe (26)** using **Xcode 26** and **Swift 6**. The current Xcode project already has a solid foundation using AppKit, SwiftUI, and AVFoundation.

---

## Table of Contents

1. [Platform & Tools Overview](#platform--tools-overview)
2. [Core Window Behavior](#1-core-window-behavior)
3. [Video Playback](#2-video-playback)
4. [Zoom & Pan](#3-zoom--pan)
5. [Opacity Control](#4-opacity-control)
6. [Lock/Ghost Mode](#5-lockghost-mode)
7. [Keyboard Shortcuts](#6-keyboard-shortcuts)
8. [Mouse/Scroll Controls](#7-mousescroll-controls)
9. [UI Elements & Liquid Glass Design](#8-ui-elements--liquid-glass-design)
10. [File Handling](#9-file-handling)
11. [Custom App Icon](#10-custom-app-icon)
12. [Framework Summary Table](#framework-summary-table)
13. [Sources](#sources)

---

## Platform & Tools Overview

### macOS Tahoe (26)
- **Released**: September 15, 2025
- **Announcement**: WWDC 2025 (June 9, 2025)
- **Design Language**: Liquid Glass
- **Final Intel Support**: macOS Tahoe is the last version supporting Intel Macs

### Xcode 26
- **Swift Version**: Swift 6
- **Minimum Deployment**: macOS 26.0 for Liquid Glass features
- **Key Features**: AI-assisted coding, ChatGPT integration, enhanced SwiftUI

### Key Frameworks Required
| Framework | Purpose |
|-----------|---------|
| **AppKit** | NSWindow management, mouse events, global shortcuts |
| **SwiftUI** | UI components, Liquid Glass materials |
| **AVFoundation** | Video playback, frame-accurate seeking |
| **AVKit** | AVPlayerLayer integration |
| **QuartzCore** | CALayer transforms for zoom/pan |
| **UniformTypeIdentifiers** | UTType for file handling |
| **ApplicationServices** | Accessibility permissions |

---

## 1. Core Window Behavior

### Requirements from FEATURES.md
- [x] Transparent, frameless window (no open/close/minimize buttons)
- [x] Always-on-top by default (with toggle)
- [x] Resizable window via native drag handles
- [x] Draggable window via control bar or bottom corner handle
- [x] Rounded corners (macOS native appearance)
- [x] Install to /Applications folder

### Framework: AppKit (NSWindow)

#### Transparent Borderless Window
```swift
import Cocoa

class TransparentWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

let window = TransparentWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: [.borderless, .resizable],
    backing: .buffered,
    defer: false
)

// Transparency configuration
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
```

**Reference**: [Apple NSWindow.StyleMask.borderless Documentation](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/borderless)

#### Always-on-Top (Floating Window)
```swift
window.level = .floating  // Or .statusBar for higher priority
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

**Reference**: [Apple NSWindow.Level Documentation](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)

#### Rounded Corners (macOS Native)
```swift
let hostingView = NSHostingView(rootView: contentView)
hostingView.wantsLayer = true
hostingView.layer?.cornerRadius = 12
hostingView.layer?.cornerCurve = .continuous  // macOS native curve
hostingView.layer?.masksToBounds = true
```

#### Window Dragging
The current implementation uses custom `NSView` subclasses with `mouseDown`/`mouseDragged` handlers. This is the correct approach for borderless windows:

```swift
class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - dragStart.x, y: current.y - dragStart.y)
        window?.setFrameOrigin(NSPoint(x: windowStart.x + delta.x, y: windowStart.y + delta.y))
    }
}
```

#### Install to /Applications
The current implementation correctly prompts users to move the app:
```swift
func ensureInstalledInApplications() {
    let bundleURL = Bundle.main.bundleURL
    let applicationsURL = URL(fileURLWithPath: "/Applications")

    guard !bundleURL.path.hasPrefix(applicationsURL.path) else { return }

    // Show alert and copy to /Applications
    let fileManager = FileManager.default
    try fileManager.copyItem(at: bundleURL, to: destinationURL)
    NSWorkspace.shared.openApplication(at: destinationURL, configuration: .init())
}
```

---

## 2. Video Playback

### Requirements from FEATURES.md
- [x] Load video files (mp4, webm, mov, avi, mkv, m4v, ProRes, HEVC, AV1)
- [x] Play/pause toggle
- [x] Timeline scrubber for seeking without lag
- [x] Frame-accurate playback (frame-by-frame stepping)
- [x] Frame number overlay display
- [x] Frame number input with keyboard incrementing
- [x] Muted by default, volume control

### Framework: AVFoundation + AVKit

#### Video Codec Support

| Codec | macOS Support | Hardware Acceleration |
|-------|---------------|----------------------|
| H.264 | All versions | Yes |
| HEVC (H.265) | macOS 10.13+ | Yes (Apple Silicon) |
| ProRes | All versions | Yes (Afterburner/M-series) |
| AV1 | macOS 14+ | M3/M4 chips only |
| VP9/WebM | Via third-party | Software only |

**Reference**: [Apple AVVideoCodecType Documentation](https://developer.apple.com/documentation/avfoundation/avvideocodectype)

**Important**: AV1 hardware decoding requires M3 or later chips. For broader compatibility, software decoding is available on macOS 14+ but may impact performance.

#### AVPlayer Setup
```swift
import AVFoundation

class VideoPlayerManager: ObservableObject {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?

    func loadVideo(url: URL, videoState: VideoState) {
        let asset = AVAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = 0  // Muted by default

        // Load metadata asynchronously (Swift Concurrency)
        Task {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.load(.tracks)

            await MainActor.run {
                videoState.duration = CMTimeGetSeconds(duration)
            }

            if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                let fps = try? await videoTrack.load(.nominalFrameRate)
                videoState.frameRate = Double(fps ?? 30.0)
                videoState.totalFrames = Int(videoState.duration * videoState.frameRate)
            }
        }
    }
}
```

**Reference**: [Apple AVPlayer Documentation](https://developer.apple.com/documentation/avfoundation/avplayer)

#### Frame-Accurate Seeking (Critical Feature)

This is the most challenging requirement. AVPlayer's default seeking uses keyframe-based seeking for performance. For **frame-accurate** seeking:

```swift
func seekToFrame(_ frame: Int, videoState: VideoState) {
    let time = Double(frame) / videoState.frameRate
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)

    // toleranceBefore: .zero, toleranceAfter: .zero = frame-accurate
    player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
        DispatchQueue.main.async {
            videoState.currentFrame = frame
            videoState.currentTime = time
        }
    }
}

func stepFrame(forward: Bool, amount: Int, videoState: VideoState) {
    player?.pause()
    videoState.isPlaying = false

    let delta = forward ? amount : -amount
    let newFrame = max(0, min(videoState.totalFrames - 1, videoState.currentFrame + delta))
    seekToFrame(newFrame, videoState: videoState)
}
```

**Note**: Frame-accurate seeking with `.zero` tolerance can be slower, especially for inter-frame codecs (H.264, HEVC). For truly instantaneous frame stepping, consider:
1. **AVAssetImageGenerator** for single frame extraction
2. **AVPlayerItemVideoOutput** with CVDisplayLink for real-time frame access

**Reference**: [Apple AVFoundation Overview](https://developer.apple.com/av-foundation/)

#### High-Performance Timeline Scrubbing
```swift
func scrub(to time: Double, videoState: VideoState) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)

    // Cancel any pending seeks for responsiveness
    player?.currentItem?.cancelPendingSeeks()

    // Use zero tolerance for accurate scrubbing
    player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)

    videoState.currentTime = time
    videoState.currentFrame = Int(time * videoState.frameRate)
}
```

---

## 3. Zoom & Pan

### Requirements from FEATURES.md
- [x] Zoom in/out using Shift+Scroll (5% increments)
- [x] Fine zoom with Cmd+Shift+Scroll (0.1% increments)
- [x] Pan video when zoomed via click+drag
- [x] Zoom scales from upper-left corner of video
- [x] Zoom percentage overlay
- [x] Zoom input with keyboard incrementing
- [x] Reset view button

### Framework: QuartzCore (CALayer) + AppKit

#### CALayer Transform for Zoom/Pan
```swift
import QuartzCore

func updateVideoTransform(playerLayer: AVPlayerLayer, scale: CGFloat, panOffset: CGSize) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)  // Disable implicit animations

    // Anchor at top-left (video corner, not window corner)
    playerLayer.anchorPoint = CGPoint(x: 0, y: 1)  // macOS coordinates

    var transform = CATransform3DIdentity
    transform = CATransform3DScale(transform, scale, scale, 1)
    transform = CATransform3DTranslate(
        transform,
        panOffset.width / scale,
        panOffset.height / scale,
        0
    )
    playerLayer.transform = transform

    CATransaction.commit()
}
```

**Critical**: The anchor point must be set to `(0, 1)` for top-left corner zooming in macOS coordinate system (origin at bottom-left).

**Reference**: [Apple CALayer Documentation](https://developer.apple.com/documentation/quartzcore/calayer)

#### Zoom State Management
```swift
class VideoState: ObservableObject {
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    var zoomPercentage: Int {
        Int((zoomScale * 100).rounded())
    }

    func adjustZoom(byPercent percent: Double) {
        let newPercentage = Double(zoomScale * 100) + percent
        let clamped = max(10.0, min(1000.0, newPercentage))
        zoomScale = CGFloat(clamped / 100.0)
    }

    func resetView() {
        zoomScale = 1.0
        panOffset = .zero
    }
}
```

**Reference**: [Scale, Rotate, Fade, and Translate NSView Animations](https://www.advancedswift.com/nsview-animations-guide/)

---

## 4. Opacity Control

### Requirements from FEATURES.md
- [x] Adjustable video opacity slider with input
- [x] Arrow key incrementing (1%, Shift for 10%)
- [x] Range from 2% to 100%

### Framework: SwiftUI + CALayer

#### Implementation
```swift
// In VideoState
@Published var opacity: Double = 1.0

func setOpacityPercentage(_ percentage: Int) {
    let clamped = max(2, min(100, percentage))
    opacity = Double(clamped) / 100.0
}

// Apply to AVPlayerLayer
playerLayer?.opacity = Float(videoState.opacity)

// Or in SwiftUI
VideoPlayerView()
    .opacity(videoState.opacity)
```

---

## 5. Lock/Ghost Mode

### Requirements from FEATURES.md
- [x] **Lock mode toggle - makes video area click-through** (CRITICAL)
- [x] Controls bar and keyboard shortcuts remain interactive when locked
- [x] Window dragging/sizing disabled when locked
- [x] Visual indicator (SF Symbols icons)

### Framework: AppKit (NSWindow.ignoresMouseEvents)

This is the most critical feature for an overlay application.

#### Click-Through Implementation
```swift
// AppDelegate or Window Controller
func setLocked(_ locked: Bool) {
    if locked {
        mainWindow.styleMask.remove(.resizable)
        mainWindow.ignoresMouseEvents = true
    } else {
        mainWindow.styleMask.insert(.resizable)
        mainWindow.ignoresMouseEvents = false
    }
}
```

**Reference**: [Apple ignoresMouseEvents Documentation](https://developer.apple.com/documentation/appkit/nswindow/1419354-ignoresmouseevents)

#### Keeping Controls Interactive

The current implementation uses a **separate child window** for controls that remains interactive:

```swift
// Controls stay interactive by being in a separate window
func createControlWindow() {
    let controlWindow = TransparentWindow(
        contentRect: controlFrame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )

    controlWindow.ignoresMouseEvents = false  // Always interactive
    mainWindow.addChildWindow(controlWindow, ordered: .above)
}
```

#### Dynamic Click-Through Based on Mouse Position
```swift
document.addEventListener('mousemove', (e) => {
    if (!isLocked) return;

    // Check if mouse is over control bar
    const rect = controls.getBoundingClientRect();
    const overControls = e.clientY >= rect.top;

    // Enable/disable click-through dynamically
    window.ignoresMouseEvents = !overControls;
});
```

**Alternative Native Approach**:
```swift
override func mouseMoved(with event: NSEvent) {
    let location = event.locationInWindow
    let controlsRect = controlsView.frame

    if controlsRect.contains(location) {
        window?.ignoresMouseEvents = false
    } else if videoState.isLocked {
        window?.ignoresMouseEvents = true
    }
}
```

---

## 6. Keyboard Shortcuts

### Requirements from FEATURES.md

#### Local Shortcuts (when app focused)
| Key | Action |
|-----|--------|
| Left/Right Arrow | Frame step |
| Shift+Left/Right | Step 10 frames |
| Up/Down Arrow | Zoom in/out (5%) |
| Shift+Up/Down | Zoom faster (10%) |
| +/- | Zoom in/out |
| 0 | Reset zoom to 100% |
| R | Reset view |
| L | Toggle lock |
| H or ? | Toggle help |
| Cmd+O | Open file |
| Esc/Enter | Defocus input, return focus |

#### Global Shortcuts (work when locked)
| Key | Action |
|-----|--------|
| Cmd+Shift+L | Toggle lock |
| Cmd+PageUp | Frame forward |
| Cmd+PageDown | Frame back |

### Framework: AppKit (NSEvent Monitors) + CGEventTap

#### Local Event Monitor
```swift
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if handleKeyEvent(event) {
        return nil  // Consume event
    }
    return event  // Pass through
}
```

#### Global Event Monitor (for shortcuts that work when app not focused)
```swift
// Requires Input Monitoring permission
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    handleGlobalKeyEvent(event)
}
```

**Important**: Global monitors **cannot modify or consume events**. They only observe.

**Reference**: [Apple addGlobalMonitorForEvents Documentation](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))

#### CGEventTap (Recommended for Global Hotkeys)

For true global hotkeys that can **intercept and consume** events:

```swift
import ApplicationServices

func setupGlobalHotkeys() {
    // Check permission first
    guard CGPreflightListenEventAccess() else {
        CGRequestListenEventAccess()
        return
    }

    let eventMask = (1 << CGEventType.keyDown.rawValue)

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { proxy, type, event, refcon in
            // Handle event
            return Unmanaged.passRetained(event)
        },
        userInfo: nil
    ) else { return }

    let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}
```

**Reference**: [Apple Developer Forums - Global Hotkeys](https://developer.apple.com/forums/thread/735223)

#### TCC Permissions for Input Monitoring

```swift
import ApplicationServices

func checkInputMonitoringPermission() -> Bool {
    return CGPreflightListenEventAccess()
}

func requestInputMonitoringPermission() {
    CGRequestListenEventAccess()
}

func openInputMonitoringSettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    NSWorkspace.shared.open(url)
}
```

**Reference**: [Accessibility Permission in macOS](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)

---

## 7. Mouse/Scroll Controls

### Requirements from FEATURES.md
- [x] Scroll wheel - Frame step (disabled in lock mode)
- [x] Shift+Scroll - Zoom 5% (disabled in lock mode)
- [x] Cmd+Shift+Scroll - Fine zoom 0.1% (disabled in lock mode)
- [x] Click+drag on video - Pan when zoomed (disabled in lock mode)
- [x] Click+drag on top bar - Move window (disabled in lock mode)
- [x] Click+drag on edges - Resize (disabled in lock mode)

### Framework: AppKit (NSView event handling)

```swift
class VideoMouseView: NSView {
    override func scrollWheel(with event: NSEvent) {
        guard let videoState = videoState, !videoState.isLocked else { return }

        let delta = event.scrollingDeltaY
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCmd = event.modifierFlags.contains(.command)

        if hasCmd && hasShift {
            // Fine zoom: 0.1% per tick
            videoState.adjustZoom(byPercent: delta > 0 ? 0.1 : -0.1)
        } else if hasShift {
            // Zoom: 5% per tick
            videoState.adjustZoom(byPercent: delta > 0 ? 5.0 : -5.0)
        } else {
            // Frame stepping
            NotificationCenter.default.post(
                name: delta > 0 ? .frameStepBackward : .frameStepForward,
                object: 1
            )
        }
    }
}
```

---

## 8. UI Elements & Liquid Glass Design

### Requirements from FEATURES.md
- [x] Drop zone for initial state
- [x] macOS Tahoe-style Liquid Glass design
- [x] Control bar with all playback controls
- [x] Help modal with keyboard shortcuts
- [x] Minimal, non-intrusive overlays

### Framework: SwiftUI (glassEffect, Materials)

#### Liquid Glass in macOS Tahoe

**New in macOS 26**: The `glassEffect` modifier provides native Liquid Glass styling:

```swift
import SwiftUI

// macOS 26+ Liquid Glass
Text("Frame: 1234")
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))

// With GlassEffectContainer for grouped elements
GlassEffectContainer {
    HStack {
        Button("Play") { }
        Button("Pause") { }
    }
    .glassEffect(.regular, in: Capsule())
}
```

**Reference**: [Build a SwiftUI app with the new design - WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)

#### Fallback for Older macOS Versions

For pre-Tahoe compatibility using `.ultraThinMaterial`:

```swift
struct GlassOverlay<Content: View>: View {
    let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 6))
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
    }
}
```

**Reference**: [iOS 26 Liquid Glass: Comprehensive Swift/SwiftUI Reference](https://medium.com/@madebyluddy/overview-37b3685227aa)

#### SF Symbols for Icons

macOS Tahoe includes **SF Symbols 7** with over 6,900 symbols:

```swift
// Lock icons
Image(systemName: "lock")
Image(systemName: "lock.fill")
Image(systemName: "lock.open")
Image(systemName: "lock.open.fill")

// Playback controls
Image(systemName: "play.fill")
Image(systemName: "pause.fill")
Image(systemName: "backward.frame.fill")
Image(systemName: "forward.frame.fill")

// Zoom
Image(systemName: "magnifyingglass")
Image(systemName: "plus.magnifyingglass")
Image(systemName: "minus.magnifyingglass")

// Other
Image(systemName: "arrow.up.left.and.arrow.down.right")  // Resize
Image(systemName: "questionmark.circle")  // Help
Image(systemName: "pin.fill")  // Always on top
Image(systemName: "film")  // Frame indicator
```

**Reference**: [SF Symbols - Apple Developer](https://developer.apple.com/sf-symbols/)

#### Dark Mode First

```swift
// Force dark mode
@main
struct VideoOverlayApp: App {
    init() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

// Or in SwiftUI view
.preferredColorScheme(.dark)
```

---

## 9. File Handling

### Requirements from FEATURES.md
- [x] Open file dialog with video filter
- [x] Support common video formats
- [x] Drag & drop video files

### Framework: AppKit (NSOpenPanel) + UniformTypeIdentifiers

#### NSOpenPanel with Video Types
```swift
import UniformTypeIdentifiers

let supportedTypes: [UTType] = [
    .mpeg4Movie,        // .mp4
    .quickTimeMovie,    // .mov
    .avi,               // .avi
    .movie,             // Generic video
    UTType("com.apple.m4v-video")!,      // .m4v
    UTType("org.matroska.mkv")!,         // .mkv (if registered)
    UTType("public.hevc")!,              // HEVC
    UTType("public.avc1")!,              // H.264
]

func openVideoFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = supportedTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = "Select a video file"

    if panel.runModal() == .OK, let url = panel.url {
        loadVideo(url: url)
    }
}
```

**Reference**: [Apple NSOpenPanel Documentation](https://developer.apple.com/documentation/appkit/nsopenpanel)

#### Drag & Drop in SwiftUI
```swift
struct DropZoneView: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        ZStack {
            // Drop zone content
        }
        .onDrop(of: [.movie, .mpeg4Movie, .quickTimeMovie], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }

            provider.loadItem(forTypeIdentifier: UTType.movie.identifier) { item, error in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        videoState.videoURL = url
                        videoState.isVideoLoaded = true
                    }
                }
            }
            return true
        }
    }
}
```

**Reference**: [SwiftUI on macOS: Drag and drop - The Eclectic Light Company](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/)

---

## 10. Custom App Icon

### Requirements from FEATURES.md
- [x] Custom application icon
- [x] Video playback area is 100% transparent

### Framework: Asset Catalog + Icon Composer (Xcode 26)

#### macOS Tahoe Icon Requirements

**New in macOS 26**: Icon Composer tool for creating Liquid Glass icons:

```
Icons required:
- icon_16x16.png
- icon_16x16@2x.png
- icon_32x32.png
- icon_32x32@2x.png
- icon_128x128.png
- icon_128x128@2x.png
- icon_256x256.png
- icon_256x256@2x.png
- icon_512x512.png
- icon_512x512@2x.png
```

Place in `Assets.xcassets/AppIcon.appiconset/`.

For macOS Tahoe's Liquid Glass icons, apps should provide:
- Light mode variant
- Dark mode variant
- Tinted variant (optional)
- Clear variant (optional)

---

## Framework Summary Table

| Feature | Primary Framework | Secondary Framework | macOS Version |
|---------|------------------|---------------------|---------------|
| Transparent Window | AppKit (NSWindow) | - | 10.0+ |
| Video Playback | AVFoundation | AVKit | 10.7+ |
| Frame-Accurate Seeking | AVFoundation | - | 10.7+ |
| Zoom/Pan | QuartzCore (CALayer) | - | 10.5+ |
| Click-Through | AppKit (ignoresMouseEvents) | - | 10.0+ |
| Global Shortcuts | CGEventTap | AppKit | 10.4+ |
| Liquid Glass UI | SwiftUI | - | **26.0+** |
| Materials (fallback) | SwiftUI | - | 12.0+ |
| SF Symbols 7 | SwiftUI/AppKit | - | **26.0+** |
| File Handling | AppKit (NSOpenPanel) | UniformTypeIdentifiers | 11.0+ |
| Drag & Drop | SwiftUI | AppKit | 11.0+ |
| HEVC Playback | AVFoundation | - | 10.13+ |
| AV1 Playback | AVFoundation | - | 14.0+ (M3+ HW) |

---

## Current Implementation Status

Based on the existing Swift code in `VideoOverlay/`:

| Feature | Status | Notes |
|---------|--------|-------|
| Transparent Window | Complete | Using TransparentWindow class |
| Always-on-Top | Complete | Using .floating level |
| Video Playback | Complete | AVFoundation + AVPlayerLayer |
| Frame-Accurate Seeking | Complete | Using .zero tolerance |
| Zoom/Pan | Complete | CALayer transforms |
| Opacity | Complete | Applied via layer opacity |
| Lock Mode | Complete | ignoresMouseEvents + child window |
| Local Shortcuts | Complete | NSEvent.addLocalMonitor |
| Global Shortcuts | Complete | NSEvent.addGlobalMonitor |
| File Dialog | Complete | NSOpenPanel |
| Drag & Drop | Partial | Needs SwiftUI onDrop |
| Liquid Glass | Not Started | Requires macOS 26 |
| SF Symbols | Partial | Some emojis used instead |

---

## Recommendations for 100% Compliance

### High Priority
1. **Replace emojis with SF Symbols** - Current implementation uses emojis (e.g., `🔒` instead of `Image(systemName: "lock")`)
2. **Add Liquid Glass styling** - When targeting macOS 26, add `glassEffect` modifiers
3. **Implement SwiftUI drag & drop** - Add `onDrop` modifier to DropZoneView

### Medium Priority
4. **Add AV1 codec support detection** - Check for M3+ hardware before attempting AV1
5. **Improve global shortcuts** - Consider CGEventTap for true event interception
6. **Add Input Monitoring permission handling** - Prompt user if needed

### Low Priority
7. **Create Liquid Glass app icon** - Use Icon Composer in Xcode 26
8. **Add WebM support** - Requires third-party codec or conversion

---

## Sources

### Apple Documentation
- [Build a SwiftUI app with the new design - WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/)
- [macOS Tahoe 26 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes)
- [Xcode 26 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
- [AVFoundation Overview](https://developer.apple.com/av-foundation/)
- [AVPlayer Documentation](https://developer.apple.com/documentation/avfoundation/avplayer)
- [NSWindow.ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/1419354-ignoresmouseevents)
- [NSWindow.StyleMask.borderless](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/borderless)
- [NSWindow.Level](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)
- [CALayer Documentation](https://developer.apple.com/documentation/quartzcore/calayer)
- [NSOpenPanel Documentation](https://developer.apple.com/documentation/appkit/nsopenpanel)
- [addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))
- [SF Symbols](https://developer.apple.com/sf-symbols/)
- [AVVideoCodecType](https://developer.apple.com/documentation/avfoundation/avvideocodectype)

### Third-Party Resources
- [iOS 26 Liquid Glass: Comprehensive Swift/SwiftUI Reference](https://medium.com/@madebyluddy/overview-37b3685227aa)
- [Liquid Glass in Swift: Official Best Practices](https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo)
- [macOS Tahoe Developer's Ultimate Guide 2025](https://macos-tahoe.com/blog/macos-tahoe-developer-ultimate-guide-2025/)
- [Create a Translucent Overlay Window on MacOS](https://gaitatzis.medium.com/create-a-translucent-overlay-window-on-macos-in-swift-67d5e000ce90)
- [NSWindowStyles GitHub Repository](https://github.com/lukakerr/NSWindowStyles)
- [CGEventSupervisor - Swift Event Monitoring](https://github.com/stephancasas/CGEventSupervisor)
- [Scale, Rotate, Fade, and Translate NSView Animations](https://www.advancedswift.com/nsview-animations-guide/)
- [SwiftUI on macOS: Drag and drop](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/)
- [Accessibility Permission in macOS](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)
- [Apple Developer Forums - Global Hotkeys](https://developer.apple.com/forums/thread/735223)

---

*Report generated: January 31, 2026*
*Target Platform: macOS Tahoe 26 / Xcode 26 / Swift 6*
