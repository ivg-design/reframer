import Cocoa
import Combine

/// Main view controller containing video view and handling keyboard shortcuts
class MainViewController: NSViewController {

    // MARK: - Properties

    let videoState: VideoState
    private var videoView: VideoView!
    private var vlcVideoView: VLCVideoView?  // Lazy-created when needed
    private var dropZoneView: DropZoneView!
    private var edgeIndicatorView: EdgeIndicatorView!
    private var cancellables = Set<AnyCancellable>()
    private var isUsingVLC = false  // Track which player is active


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
        view.addSubview(videoView)

        dropZoneView = DropZoneView()
        dropZoneView.translatesAutoresizingMaskIntoConstraints = false
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
                if self.isUsingVLC {
                    self.videoView?.isHidden = true
                    self.vlcVideoView?.isHidden = !isLoaded
                } else {
                    self.videoView?.isHidden = !isLoaded
                    self.vlcVideoView?.isHidden = true
                }
            }
            .store(in: &cancellables)

        // Observe video URL changes to decide which player to use
        videoState.$videoURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                if let url = url {
                    self?.handleVideoURLChange(url)
                }
            }
            .store(in: &cancellables)

        // Fallback if AVFoundation fails (unsupported codec in supported container)
        NotificationCenter.default.publisher(for: .avFoundationPlaybackFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self, let url = self.videoState.videoURL else { return }
                guard self.videoState.playbackEngine == .auto else { return }
                if self.videoState.videoAudioURL != nil {
                    return
                }
                if VLCKitManager.shared.isReady {
                    self.switchToVLCPlayer(url: url)
                } else if VLCKitManager.shared.isInstalled && !VLCKitManager.shared.isEnabled {
                    self.showEnableVLCKitPrompt(url: url)
                } else {
                    self.showInstallVLCKitPrompt(url: url)
                }
            }
            .store(in: &cancellables)

        // Initial state
        dropZoneView?.isHidden = videoState.isVideoLoaded
        videoView?.isHidden = !videoState.isVideoLoaded
    }

    // MARK: - Video Player Selection

    private func handleVideoURLChange(_ url: URL) {
        let manager = VLCKitManager.shared

        switch videoState.playbackEngine {
        case .vlc:
            if manager.isReady {
                switchToVLCPlayer(url: url)
            } else if manager.isInstalled && !manager.isEnabled {
                showEnableVLCKitPrompt(url: url)
            } else {
                showInstallVLCKitPrompt(url: url)
            }
        case .avFoundation:
            switchToAVPlayer()
        case .auto:
            if manager.requiresVLCKit(url: url) {
                if manager.isReady {
                    switchToVLCPlayer(url: url)
                } else if manager.isInstalled && !manager.isEnabled {
                    showEnableVLCKitPrompt(url: url)
                } else {
                    showInstallVLCKitPrompt(url: url)
                }
            } else {
                switchToAVPlayer()
            }
        }
    }

    private func switchToAVPlayer() {
        isUsingVLC = false
        vlcVideoView?.isHidden = true
        videoView?.isHidden = false
    }

    private func switchToVLCPlayer(url: URL) {
        isUsingVLC = true
        videoView?.isHidden = true

        // Create VLC view if needed
        if vlcVideoView == nil {
            let vlcView = VLCVideoView()
            vlcView.translatesAutoresizingMaskIntoConstraints = false
            vlcView.videoState = videoState
            view.addSubview(vlcView, positioned: .below, relativeTo: dropZoneView)

            NSLayoutConstraint.activate([
                vlcView.topAnchor.constraint(equalTo: view.topAnchor),
                vlcView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                vlcView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                vlcView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            vlcVideoView = vlcView
        }

        vlcVideoView?.isHidden = false
        vlcVideoView?.loadVideo(url: url)
    }

    private func showInstallVLCKitPrompt(url: URL) {
        let alert = NSAlert()
        alert.messageText = "Extended Format Support Required"
        alert.informativeText = "\(url.pathExtension.uppercased()) files require VLC for playback. Would you like to install it now (~140MB download)?"
        alert.addButton(withTitle: "Install VLCKit")
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else { return }

        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                // Install directly
                self?.installVLCKitAndPlay(url: url)
            case .alertSecondButtonReturn:
                // Open preferences
                PreferencesWindowController.shared.showWindow()
            default:
                break
            }
        }
    }

    private func showEnableVLCKitPrompt(url: URL) {
        let alert = NSAlert()
        alert.messageText = "Enable Extended Format Support?"
        alert.informativeText = "\(url.pathExtension.uppercased()) files require VLCKit. VLCKit is installed but disabled. Enable it?"
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else { return }

        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                VLCKitManager.shared.isEnabled = true
                VLCKitManager.shared.loadFramework()
                self?.switchToVLCPlayer(url: url)
            }
        }
    }

    private func installVLCKitAndPlay(url: URL) {
        let progressAlert = NSAlert()
        progressAlert.messageText = "Installing VLCKit..."
        progressAlert.informativeText = "Downloading..."
        progressAlert.addButton(withTitle: "Cancel")

        let progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.frame = NSRect(x: 0, y: 0, width: 250, height: 20)
        progressAlert.accessoryView = progressIndicator

        guard let window = view.window else { return }

        progressAlert.beginSheetModal(for: window) { _ in }

        VLCKitManager.shared.install { progress, status in
            progressIndicator.doubleValue = progress
            progressAlert.informativeText = status
        } completion: { [weak self] result in
            window.endSheet(window.attachedSheet!)

            switch result {
            case .success:
                VLCKitManager.shared.isEnabled = true
                self?.switchToVLCPlayer(url: url)
            case .failure(let error):
                let errorAlert = NSAlert()
                errorAlert.messageText = "Installation Failed"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .critical
                errorAlert.beginSheetModal(for: window)
            }
        }
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
        case 31 where cmd && !shift:
            NotificationCenter.default.post(name: .openVideo, object: nil)
            return true

        // Space - Play/Pause
        case 49 where flags.isEmpty && videoState.isVideoLoaded:
            videoState.isPlaying.toggle()
            return true

        // Arrow keys - Pan (when unlocked)
        case 123 where videoState.isVideoLoaded && !videoState.isLocked: // Left
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.width -= amount
            return true

        case 124 where videoState.isVideoLoaded && !videoState.isLocked: // Right
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.width += amount
            return true

        case 126 where videoState.isVideoLoaded && !videoState.isLocked: // Up
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.height += amount
            return true

        case 125 where videoState.isVideoLoaded && !videoState.isLocked: // Down
            let amount = cmd && shift ? 100.0 : (shift ? 10.0 : 1.0)
            videoState.panOffset.height -= amount
            return true

        // 0 - Reset zoom to 100%
        case 29 where videoState.isVideoLoaded && !videoState.isLocked && flags.isEmpty:
            videoState.zoomScale = 1.0
            return true

        // R - Reset view (zoom and pan)
        case 15 where flags.isEmpty && !videoState.isLocked:
            videoState.resetView()
            return true

        // L - Toggle lock
        case 37 where flags.isEmpty:
            videoState.isLocked.toggle()
            return true

        // H - Toggle help
        case 4 where flags.isEmpty:
            videoState.showHelp.toggle()
            return true

        // ? (Shift+/) - Toggle help
        case 44 where shift:
            videoState.showHelp.toggle()
            return true

        // Esc - Close help if open
        case 53 where videoState.showHelp:
            videoState.showHelp = false
            return true

        default:
            return false
        }
    }
}
