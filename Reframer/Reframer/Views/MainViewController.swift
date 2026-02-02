import Cocoa
import Combine

/// Main view controller containing video view and handling keyboard shortcuts
class MainViewController: NSViewController {

    // MARK: - Properties

    let videoState: VideoState
    private var videoView: VideoView!
    private var mpvVideoView: MPVVideoView?  // Lazy-created when needed
    private var dropZoneView: DropZoneView!
    private var edgeIndicatorView: EdgeIndicatorView!
    private var cancellables = Set<AnyCancellable>()
    private var isUsingMPV = false  // Track which player is active


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

        // Preload libmpv if enabled
        MPVManager.shared.loadLibrary()

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
                if self.isUsingMPV {
                    self.videoView?.isHidden = true
                    self.mpvVideoView?.isHidden = !isLoaded
                } else {
                    self.videoView?.isHidden = !isLoaded
                    self.mpvVideoView?.isHidden = true
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
            .sink { [weak self] _ in
                guard let self = self, let url = self.videoState.videoURL else { return }
                guard self.videoState.playbackEngine == .auto else { return }
                // YouTube streaming is handled by MPV; skip AVFoundation fallback.
                if self.videoState.videoAudioURL != nil {
                    return
                }
                if MPVManager.shared.isReady {
                    self.switchToMPVPlayer(url: url)
                } else if MPVManager.shared.isInstalled && !MPVManager.shared.isEnabled {
                    self.showEnableMPVPrompt(url: url)
                } else {
                    self.showInstallMPVPrompt(url: url)
                }
            }
            .store(in: &cancellables)

        // Initial state
        dropZoneView?.isHidden = videoState.isVideoLoaded
        videoView?.isHidden = !videoState.isVideoLoaded
    }

    // MARK: - Video Player Selection

    private func handleVideoURLChange(_ url: URL) {
        let manager = MPVManager.shared

        print("MainViewController: === handleVideoURLChange ===")
        print("MainViewController: URL = \(url.lastPathComponent)")
        print("MainViewController: Full URL = \(url.absoluteString.prefix(100))...")
        print("MainViewController: playbackEngine = \(videoState.playbackEngine)")
        print("MainViewController: videoAudioURL = \(videoState.videoAudioURL?.absoluteString.prefix(50) ?? "nil")")
        print("MainViewController: MPVManager.isReady = \(manager.isReady)")
        print("MainViewController: isInstalled = \(manager.isInstalled)")
        print("MainViewController: isEnabled = \(manager.isEnabled)")
        print("MainViewController: requiresMPV = \(manager.requiresMPV(url: url))")

        // Check if this is a YouTube stream (has separate audio URL or headers)
        let isYouTubeStream = videoState.videoAudioURL != nil || videoState.videoHeaders != nil

        // YouTube streams: require MPV (AVFoundation is too slow - 60+ seconds vs 2-5 seconds)
        if isYouTubeStream {
            print("MainViewController: YouTube stream detected, routing to MPV")
            if manager.isReady {
                print("MainViewController: MPV ready, switching to MPV player for YouTube")
                switchToMPVPlayerForYouTube()
            } else if manager.isInstalled && !manager.isEnabled {
                print("MainViewController: MPV installed but not enabled")
                showEnableMPVPromptForYouTube()
            } else {
                print("MainViewController: MPV not available, showing install prompt")
                showInstallMPVPromptForYouTube()
            }
            return
        }

        switch videoState.playbackEngine {
        case .mpv:
            if manager.isReady {
                switchToMPVPlayer(url: url)
            } else if manager.isInstalled && !manager.isEnabled {
                showEnableMPVPrompt(url: url)
            } else {
                showInstallMPVPrompt(url: url)
            }
        case .avFoundation:
            switchToAVPlayer()
        case .auto:
            // Fast path for known MPV-only formats
            if manager.requiresMPV(url: url) {
                if manager.isReady {
                    switchToMPVPlayer(url: url)
                } else if manager.isInstalled && !manager.isEnabled {
                    showEnableMPVPrompt(url: url)
                } else {
                    showInstallMPVPrompt(url: url)
                }
            } else {
                // Proactive codec detection: check if AVFoundation can actually decode
                Task {
                    let canPlay = await VideoFormats.canAVFoundationPlay(url)
                    await MainActor.run {
                        if canPlay {
                            self.switchToAVPlayer()
                        } else if manager.isReady {
                            // AVFoundation can't play this (e.g., VP9 in MP4)
                            self.switchToMPVPlayer(url: url)
                        } else if manager.isInstalled && !manager.isEnabled {
                            self.showEnableMPVPrompt(url: url)
                        } else {
                            // No MPV available, try AVFoundation anyway (will show error if it fails)
                            self.switchToAVPlayer()
                        }
                    }
                }
            }
        }
    }

    private func switchToAVPlayer() {
        print("MainViewController: Switching to AVFoundation player")
        isUsingMPV = false

        // Stop any MPV playback to prevent stale errors from appearing
        mpvVideoView?.stop()
        mpvVideoView?.isHidden = true

        videoView?.isHidden = false
    }

    private func switchToMPVPlayer(url: URL) {
        print("MainViewController: Switching to MPV player for \(url.lastPathComponent)")
        isUsingMPV = true
        videoView?.isHidden = true

        // Create MPV view if needed
        if mpvVideoView == nil {
            let mpvView = MPVVideoView(frame: .zero)
            mpvView.translatesAutoresizingMaskIntoConstraints = false
            mpvView.videoState = videoState
            view.addSubview(mpvView, positioned: .below, relativeTo: dropZoneView)

            NSLayoutConstraint.activate([
                mpvView.topAnchor.constraint(equalTo: view.topAnchor),
                mpvView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                mpvView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                mpvView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            mpvVideoView = mpvView
        }

        mpvVideoView?.isHidden = false
        mpvVideoView?.loadVideo(url: url)
    }

    private func switchToMPVPlayerForYouTube() {
        guard let videoURL = videoState.videoURL else { return }
        print("MainViewController: Switching to MPV player for YouTube stream")
        isUsingMPV = true
        videoView?.isHidden = true

        // Create MPV view if needed
        if mpvVideoView == nil {
            let mpvView = MPVVideoView(frame: .zero)
            mpvView.translatesAutoresizingMaskIntoConstraints = false
            mpvView.videoState = videoState
            view.addSubview(mpvView, positioned: .below, relativeTo: dropZoneView)

            NSLayoutConstraint.activate([
                mpvView.topAnchor.constraint(equalTo: view.topAnchor),
                mpvView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                mpvView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                mpvView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])

            mpvVideoView = mpvView
        }

        mpvVideoView?.isHidden = false
        mpvVideoView?.loadYouTubeVideo(
            videoURL: videoURL,
            audioURL: videoState.videoAudioURL,
            headers: videoState.videoHeaders
        )
    }

    private func showInstallMPVPromptForYouTube() {
        print("MainViewController: showInstallMPVPromptForYouTube called")

        let alert = NSAlert()
        alert.messageText = "Install MPV for YouTube Playback"
        alert.informativeText = "YouTube playback requires MPV. Would you like to install it now? (Downloads ~30MB)"
        alert.addButton(withTitle: "Install MPV")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else {
            print("MainViewController: ERROR - view.window is nil, deferring prompt")
            // Defer showing prompt until window is available
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showInstallMPVPromptForYouTube()
            }
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.installMPVAndPlayYouTube()
            }
        }
    }

    private func showEnableMPVPromptForYouTube() {
        let alert = NSAlert()
        alert.messageText = "Enable MPV for YouTube Playback"
        alert.informativeText = "YouTube playback requires MPV. libmpv is installed but disabled. Enable it?"
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showEnableMPVPromptForYouTube()
            }
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                MPVManager.shared.isEnabled = true
                MPVManager.shared.loadLibrary()
                if MPVManager.shared.isReady {
                    self?.switchToMPVPlayerForYouTube()
                } else {
                    self?.showMPVLoadFailure()
                }
            }
        }
    }

    private func installMPVAndPlayYouTube() {
        let progressAlert = NSAlert()
        progressAlert.messageText = "Installing MPV..."
        progressAlert.informativeText = "Downloading..."
        progressAlert.addButton(withTitle: "Cancel")

        let progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.frame = NSRect(x: 0, y: 0, width: 250, height: 20)
        progressAlert.accessoryView = progressIndicator

        guard let window = view.window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showInstallMPVPrompt(url: url)
            }
            return
        }

        progressAlert.beginSheetModal(for: window) { _ in }

        MPVManager.shared.install { progress, status in
            progressIndicator.doubleValue = progress
            progressAlert.informativeText = status
        } completion: { [weak self] result in
            window.endSheet(window.attachedSheet!)

            switch result {
            case .success:
                MPVManager.shared.isEnabled = true
                MPVManager.shared.loadLibrary()
                if MPVManager.shared.isReady {
                    self?.switchToMPVPlayerForYouTube()
                } else {
                    self?.showMPVLoadFailure()
                }
            case .failure(let error):
                let errorAlert = NSAlert()
                errorAlert.messageText = "Installation Failed"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .critical
                errorAlert.addButton(withTitle: "Retry")
                errorAlert.addButton(withTitle: "Cancel")
                errorAlert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn {
                        self?.installMPVAndPlayYouTube()
                    }
                }
            }
        }
    }

    private func showInstallMPVPrompt(url: URL) {
        let alert = NSAlert()
        alert.messageText = "Extended Format Support Required"
        alert.informativeText = "\(url.pathExtension.uppercased()) files require libmpv for playback. Would you like to install it now?"
        alert.addButton(withTitle: "Install MPV")
        alert.addButton(withTitle: "Open Preferences")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showEnableMPVPrompt(url: url)
            }
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                // Install directly
                self?.installMPVAndPlay(url: url)
            case .alertSecondButtonReturn:
                // Open preferences
                PreferencesWindowController.shared.showWindow()
            default:
                break
            }
        }
    }

    private func showEnableMPVPrompt(url: URL) {
        let alert = NSAlert()
        alert.messageText = "Enable Extended Format Support?"
        alert.informativeText = "\(url.pathExtension.uppercased()) files require libmpv. libmpv is installed but disabled. Enable it?"
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")

        guard let window = view.window else { return }

        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                MPVManager.shared.isEnabled = true
                MPVManager.shared.loadLibrary()
                if MPVManager.shared.isReady {
                    self?.switchToMPVPlayer(url: url)
                } else {
                    self?.showMPVLoadFailure()
                }
            }
        }
    }

    private func installMPVAndPlay(url: URL) {
        let progressAlert = NSAlert()
        progressAlert.messageText = "Installing MPV..."
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

        MPVManager.shared.install { progress, status in
            progressIndicator.doubleValue = progress
            progressAlert.informativeText = status
        } completion: { [weak self] result in
            window.endSheet(window.attachedSheet!)

            switch result {
            case .success:
                MPVManager.shared.isEnabled = true
                MPVManager.shared.loadLibrary()
                if MPVManager.shared.isReady {
                    self?.switchToMPVPlayer(url: url)
                } else {
                    self?.showMPVLoadFailure()
                }
            case .failure(let error):
                let errorAlert = NSAlert()
                errorAlert.messageText = "Installation Failed"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .critical
                errorAlert.beginSheetModal(for: window)
            }
        }
    }

    private func showMPVLoadFailure() {
        let alert = NSAlert()
        alert.messageText = "MPV Could Not Be Loaded"
        alert.informativeText = "libmpv installed but failed to load. Try reinstalling MPV from Preferences."
        alert.alertStyle = .critical
        if let window = view.window {
            alert.beginSheetModal(for: window)
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
