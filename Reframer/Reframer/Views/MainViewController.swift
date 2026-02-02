import Cocoa
import Combine

/// Main view controller containing video view and handling keyboard shortcuts
class MainViewController: NSViewController {

    // MARK: - Properties

    let videoState: VideoState
    private var videoView: VideoView!
    private var dropZoneView: DropZoneView!
    private var edgeIndicatorView: EdgeIndicatorView!
    private var cancellables = Set<AnyCancellable>()


    // MARK: - Initialization

    init(videoState: VideoState) {
        self.videoState = videoState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        // This view controller must be initialized programmatically with a VideoState
        return nil
    }

    // MARK: - View Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.cornerRadius = 12
        // Round ALL corners - toolbar is now BELOW the window, not overlapping
        view.layer?.masksToBounds = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Create views programmatically
        videoView = VideoView()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.setAccessibilityIdentifier("video-view")
        view.addSubview(videoView)

        dropZoneView = DropZoneView()
        dropZoneView.translatesAutoresizingMaskIntoConstraints = false
        dropZoneView.setAccessibilityIdentifier("drop-zone")
        view.addSubview(dropZoneView)

        // Edge indicator view for resize hints (pulsing edges when unlocked)
        edgeIndicatorView = EdgeIndicatorView()
        edgeIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edgeIndicatorView)

        // Configure views
        videoView.videoState = videoState
        dropZoneView.videoState = videoState
        edgeIndicatorView.videoState = videoState

        // Add constraints - content fills entire view (toolbar is now BELOW window)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dropZoneView.topAnchor.constraint(equalTo: view.topAnchor),
            dropZoneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dropZoneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dropZoneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            edgeIndicatorView.topAnchor.constraint(equalTo: view.topAnchor),
            edgeIndicatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            edgeIndicatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            edgeIndicatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Bind opacity
        videoState.$opacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] opacity in
                self?.view.alphaValue = opacity
            }
            .store(in: &cancellables)

        // Show/hide drop zone based on video loaded state
        videoState.$isVideoLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoaded in
                guard let self = self else { return }
                self.dropZoneView?.isHidden = isLoaded
                self.videoView?.isHidden = !isLoaded
            }
            .store(in: &cancellables)

        // Initial state
        dropZoneView?.isHidden = videoState.isVideoLoaded
        videoView?.isHidden = !videoState.isVideoLoaded
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Make this controller the first responder for keyboard events
        view.window?.makeFirstResponder(self)

        // Also observe window becoming key to restore first responder
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: view.window
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        view.window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        return super.becomeFirstResponder()
    }

    // MARK: - Keyboard Handling

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift)
        let cmd = flags.contains(.command)

        switch event.keyCode {
        // Cmd+O - Open video
        case KeyCode.o where cmd && !shift:
            NotificationCenter.default.post(name: .openVideo, object: nil)
            return true

        // Space - Play/Pause
        case KeyCode.space where flags.isEmpty && videoState.isVideoLoaded:
            videoState.isPlaying.toggle()
            return true

        // Arrow keys - Pan (when unlocked)
        case KeyCode.leftArrow where videoState.isVideoLoaded && !videoState.isLocked: // Left
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.width -= amount
            return true

        case KeyCode.rightArrow where videoState.isVideoLoaded && !videoState.isLocked: // Right
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.width += amount
            return true

        case KeyCode.upArrow where videoState.isVideoLoaded && !videoState.isLocked: // Up
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.height += amount
            return true

        case KeyCode.downArrow where videoState.isVideoLoaded && !videoState.isLocked: // Down
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.height -= amount
            return true

        // 0 - Reset zoom to 100%
        case KeyCode.zero where videoState.isVideoLoaded && !videoState.isLocked && flags.isEmpty:
            videoState.zoomScale = 1.0
            return true

        // R - Reset view (zoom and pan)
        case KeyCode.r where flags.isEmpty && !videoState.isLocked:
            videoState.resetView()
            return true

        // L - Toggle lock
        case KeyCode.l where flags.isEmpty:
            videoState.isLocked.toggle()
            return true

        // H - Toggle help
        case KeyCode.h where flags.isEmpty:
            videoState.showHelp.toggle()
            return true

        // ? (Shift+/) - Toggle help
        case KeyCode.questionMark where shift:
            videoState.showHelp.toggle()
            return true

        // Esc - Close help if open
        case KeyCode.escape where videoState.showHelp:
            videoState.showHelp = false
            return true

        default:
            return false
        }
    }
}
