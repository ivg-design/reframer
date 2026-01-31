import SwiftUI

struct ContentView: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        ZStack {
            // Main content
            if videoState.isVideoLoaded {
                VideoPlayerView()
                    .opacity(videoState.opacity)
            } else {
                DropZoneView()
            }

            // Overlays when video loaded
            if videoState.isVideoLoaded {
                VStack {
                    HStack(alignment: .top) {
                        FrameOverlay().padding(12)
                        Spacer()
                        ZoomOverlay().padding(12)
                    }
                    Spacer()
                }
            }

            // Drag handle bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    WindowDragHandle()
                        .padding(4)
                }
            }

            // Lock indicator
            VStack {
                LockIndicator().padding(.top, 50)
                Spacer()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onReceive(NotificationCenter.default.publisher(for: .openVideo)) { _ in
            openVideoFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLock)) { _ in
            videoState.isLocked.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .seekToTime)) { n in
            if let time = n.object as? Double {
                NotificationCenter.default.post(name: .seekToTimeInternal, object: time)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seekToFrame)) { n in
            if let frame = n.object as? Int {
                NotificationCenter.default.post(name: .seekToFrameInternal, object: frame)
            }
        }
        .handleKeyboardShortcuts()
    }

    private func openVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFormats.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a video file"

        if panel.runModal() == .OK, let url = panel.url {
            videoState.videoURL = url
            videoState.isVideoLoaded = true
        }
    }
}

// MARK: - Frame Overlay

struct FrameOverlay: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "film")
                .font(.system(size: 10))
            Text("\(videoState.currentFrame) / \(videoState.totalFrames)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .modifier(GlassBackgroundModifier(cornerRadius: 6))
    }
}

// MARK: - Zoom Overlay

struct ZoomOverlay: View {
    @EnvironmentObject var videoState: VideoState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
            Text("\(videoState.zoomPercentage)%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .modifier(GlassBackgroundModifier(cornerRadius: 6))
    }
}

// MARK: - Window Drag View (wraps content, enables window dragging)

struct WindowDragView<Content: View>: NSViewRepresentable {
    @EnvironmentObject var videoState: VideoState
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        let hostingView = NSHostingView(rootView: content.environmentObject(videoState))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.videoState = videoState
    }
}

class WindowDragNSView: NSView {
    weak var videoState: VideoState?
    private var dragStart: NSPoint = .zero
    private var windowStart: NSPoint = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hitView = hit, hitView !== self else { return self }

        var view: NSView? = hitView
        while let current = view {
            if current is NSControl || current is NSTextView {
                return hitView
            }
            view = current.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if videoState?.isLocked == true {
            super.mouseDown(with: event)
            return
        }
        dragStart = NSEvent.mouseLocation
        windowStart = (window?.parent ?? window)?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        if videoState?.isLocked == true { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y
        (window?.parent ?? window)?.setFrameOrigin(NSPoint(x: windowStart.x + dx, y: windowStart.y + dy))
    }
}

// MARK: - Window Drag Handle (bottom right corner)

struct WindowDragHandle: View {
    @EnvironmentObject var videoState: VideoState
    @State private var isHovering = false

    var body: some View {
        WindowDragHandleNSView(videoState: videoState)
            .frame(width: 44, height: 44)
            .opacity(videoState.isLocked ? 0.3 : 1)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering && !videoState.isLocked {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .overlay {
                if isHovering && !videoState.isLocked {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .modifier(GlassBackgroundModifier(cornerRadius: 4))
                }
            }
    }
}

struct WindowDragHandleNSView: NSViewRepresentable {
    let videoState: VideoState

    func makeNSView(context: Context) -> DragHandleNSView {
        let view = DragHandleNSView()
        view.videoState = videoState
        return view
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        nsView.videoState = videoState
    }
}

class DragHandleNSView: NSView {
    weak var videoState: VideoState?
    private var dragStart: NSPoint = .zero
    private var windowStart: NSPoint = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if videoState?.isLocked == true { return }
        dragStart = NSEvent.mouseLocation
        windowStart = (window?.parent ?? window)?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        if videoState?.isLocked == true { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y
        (window?.parent ?? window)?.setFrameOrigin(NSPoint(x: windowStart.x + dx, y: windowStart.y + dy))
    }
}

// MARK: - Keyboard Shortcuts

struct KeyboardShortcutsModifier: ViewModifier {
    @EnvironmentObject var videoState: VideoState

    func body(content: Content) -> some View {
        content.onAppear {
            KeyboardShortcutMonitor.shared.installIfNeeded { event in
                if handleKey(event) { return nil }
                return event
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let responder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder
        if responder is NSTextView {
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
        case 31 where flags == .command:
            NotificationCenter.default.post(name: .openVideo, object: nil)
            return true
        case 49 where videoState.isVideoLoaded && flags.isEmpty:
            videoState.isPlaying.toggle()
            return true
        case 123 where videoState.isVideoLoaded:
            NotificationCenter.default.post(name: .frameStepBackward, object: shift ? 10 : 1)
            return true
        case 124 where videoState.isVideoLoaded:
            NotificationCenter.default.post(name: .frameStepForward, object: shift ? 10 : 1)
            return true
        case 126 where videoState.isVideoLoaded && !videoState.isLocked:
            videoState.adjustZoom(byPercent: shift ? 10 : 5)
            return true
        case 125 where videoState.isVideoLoaded && !videoState.isLocked:
            videoState.adjustZoom(byPercent: shift ? -10 : -5)
            return true
        case 24 where videoState.isVideoLoaded && !videoState.isLocked:
            videoState.adjustZoom(byPercent: 5)
            return true
        case 27 where videoState.isVideoLoaded && !videoState.isLocked:
            videoState.adjustZoom(byPercent: -5)
            return true
        case 29 where videoState.isVideoLoaded && !videoState.isLocked && flags.isEmpty:
            videoState.zoomScale = 1.0
            return true
        case 15 where flags.isEmpty && !videoState.isLocked:
            videoState.resetView()
            return true
        case 37 where flags.isEmpty:
            videoState.isLocked.toggle()
            return true
        case 4 where flags.isEmpty:
            videoState.showHelp.toggle()
            return true
        case 44 where shift:
            videoState.showHelp.toggle()
            return true
        case 53 where videoState.showHelp:
            videoState.showHelp = false
            return true
        default:
            return false
        }
    }
}

extension View {
    func handleKeyboardShortcuts() -> some View {
        modifier(KeyboardShortcutsModifier())
    }
}

final class KeyboardShortcutMonitor {
    static let shared = KeyboardShortcutMonitor()
    private var monitor: Any?

    private init() {}

    func installIfNeeded(handler: @escaping (NSEvent) -> NSEvent?) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let seekToTime = Notification.Name("seekToTime")
    static let seekToFrame = Notification.Name("seekToFrame")
    static let seekToTimeInternal = Notification.Name("seekToTimeInternal")
    static let seekToFrameInternal = Notification.Name("seekToFrameInternal")
}
