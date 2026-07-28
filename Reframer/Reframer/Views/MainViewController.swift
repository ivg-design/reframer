import Cocoa
import Combine

enum MainPresentationState: Equatable {
    case empty
    case loading
    case ready
    case failed(String)

    static func resolve(
        isLoaded: Bool,
        isLoading: Bool,
        errorMessage: String?
    ) -> MainPresentationState {
        if let errorMessage, !errorMessage.isEmpty {
            return .failed(errorMessage)
        }
        if isLoading {
            return .loading
        }
        return isLoaded ? .ready : .empty
    }
}

/// Main view controller containing video view and handling keyboard shortcuts
class MainViewController: NSViewController {

    // MARK: - Properties

    let videoState: VideoState
    private var videoView: VideoView!
    private var dropZoneView: DropZoneView!
    private var edgeIndicatorView: EdgeIndicatorView!
    private var loadingView: NSStackView!
    private var errorView: NSStackView!
    private var errorLabel: NSTextField!
    private var retryButton: NSButton!
    private var filterErrorLabel: NSTextField!
    private var presentationState: MainPresentationState = .empty
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

        loadingView = makeLoadingView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)

        errorView = makeErrorView()
        errorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorView)

        filterErrorLabel = NSTextField(wrappingLabelWithString: "")
        filterErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        filterErrorLabel.alignment = .center
        filterErrorLabel.textColor = .systemRed
        filterErrorLabel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88)
        filterErrorLabel.drawsBackground = true
        filterErrorLabel.setAccessibilityIdentifier("filter-error")
        filterErrorLabel.setAccessibilityRole(.staticText)
        filterErrorLabel.isHidden = true
        view.addSubview(filterErrorLabel)

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

            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loadingView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            loadingView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            errorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            errorView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            filterErrorLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            filterErrorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            filterErrorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            filterErrorLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            edgeIndicatorView.topAnchor.constraint(equalTo: view.topAnchor),
            edgeIndicatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            edgeIndicatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            edgeIndicatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Bind opacity
        videoState.$opacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] opacity in
                self?.videoView.alphaValue = opacity
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            videoState.$isVideoLoaded,
            videoState.$isVideoLoading,
            videoState.$videoErrorMessage
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoaded, isLoading, errorMessage in
                self?.show(
                    MainPresentationState.resolve(
                        isLoaded: isLoaded,
                        isLoading: isLoading,
                        errorMessage: errorMessage
                    )
                )
            }
            .store(in: &cancellables)

        videoState.$filterErrorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.filterErrorLabel.stringValue = message ?? ""
                self?.filterErrorLabel.isHidden = message == nil
            }
            .store(in: &cancellables)

        show(
            MainPresentationState.resolve(
                isLoaded: videoState.isVideoLoaded,
                isLoading: videoState.isVideoLoading,
                errorMessage: videoState.videoErrorMessage
            )
        )
    }

    private func makeLoadingView() -> NSStackView {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        spinner.setAccessibilityElement(false)

        let label = NSTextField(labelWithString: "Loading video…")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel("Loading video")
        stack.setAccessibilityIdentifier("loading-state")
        return stack
    }

    private func makeErrorView() -> NSStackView {
        let title = NSTextField(labelWithString: "Video couldn’t be opened")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center

        errorLabel = NSTextField(wrappingLabelWithString: "")
        errorLabel.alignment = .center
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.maximumNumberOfLines = 4
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        retryButton = NSButton(title: "Retry", target: self, action: #selector(retryVideo))
        retryButton.keyEquivalent = "\r"
        retryButton.setAccessibilityIdentifier("button-retry-video")
        retryButton.setAccessibilityHelp("Try loading the same video again")

        let chooseButton = NSButton(
            title: "Choose Another Video…",
            target: self,
            action: #selector(chooseAnotherVideo)
        )
        chooseButton.setAccessibilityIdentifier("button-choose-another-video")
        chooseButton.setAccessibilityHelp("Open a different MP4, M4V, or MOV video")

        let buttons = NSStackView(views: [retryButton, chooseButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel("Video load failed")
        stack.setAccessibilityIdentifier("error-state")
        return stack
    }

    private func show(_ state: MainPresentationState) {
        let previous = presentationState
        presentationState = state

        dropZoneView.isHidden = state != .empty
        loadingView.isHidden = state != .loading
        videoView.isHidden = state != .ready
        edgeIndicatorView.isHidden = state != .ready

        if case .failed(let message) = state {
            errorView.isHidden = false
            errorLabel.stringValue = message
            errorView.setAccessibilityHelp(message)
            if previous != state, view.window?.isKeyWindow == true {
                view.window?.makeFirstResponder(retryButton)
            }
        } else {
            errorView.isHidden = true
        }
    }

    @objc private func retryVideo(_ sender: Any?) {
        videoState.reloadVideo()
    }

    @objc private func chooseAnotherVideo(_ sender: Any?) {
        NotificationCenter.default.post(name: .openVideo, object: nil)
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
