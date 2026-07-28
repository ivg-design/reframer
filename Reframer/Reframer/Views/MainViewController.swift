import Cocoa
import Combine

struct AccessibilityErrorAnnouncementTracker {
    private(set) var lastMessage: String?

    mutating func newMessageToAnnounce(_ message: String?) -> String? {
        let normalized = message.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard normalized != lastMessage else { return nil }
        lastMessage = normalized
        return normalized
    }
}

func postAccessibilityErrorAnnouncement(_ message: String, from element: Any) {
    NSAccessibility.post(
        element: element,
        notification: .announcementRequested,
        userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ]
    )
}

struct ReadyStatusOverlaySnapshot: Equatable {
    let frameText: String
    let zoomText: String
    let lockText: String
    let isLocked: Bool

    init(currentFrame: Int, totalFrames: Int, zoomScale: CGFloat, isLocked: Bool) {
        let safeFrame = max(0, currentFrame)
        let safeTotal = max(0, totalFrames)
        let percentage = zoomScale.isFinite
            ? max(10, min(1000, Double(zoomScale * 100)))
            : 100

        frameText = "Frame \(safeFrame) / \(safeTotal)"
        if abs(percentage.rounded() - percentage) < 0.000_1 {
            zoomText = "Zoom \(Int(percentage.rounded()))%"
        } else {
            zoomText = String(format: "Zoom %.1f%%", percentage)
        }
        lockText = isLocked ? "Locked" : "Unlocked"
        self.isLocked = isLocked
    }
}

private final class StatusBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var isAccent = false
    private var displayedText = ""

    init(identifier: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier(identifier)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityLabel(accessibilityLabel)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byClipping
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setAccessibilityElement(false)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(text: String, accent: Bool = false) {
        if displayedText != text {
            displayedText = text
            label.stringValue = text
            setAccessibilityValue(text)
        }
        if isAccent != accent {
            isAccent = accent
            updateAppearance()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let self else { return }
            let reduceTransparency =
                NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if isAccent {
                layer?.backgroundColor = (
                    reduceTransparency
                        ? NSColor.systemRed
                        : NSColor.systemRed.withAlphaComponent(0.82)
                ).cgColor
                label.textColor = .white
            } else {
                layer?.backgroundColor = (
                    reduceTransparency
                        ? NSColor.windowBackgroundColor
                        : NSColor.black.withAlphaComponent(0.58)
                ).cgColor
                label.textColor = reduceTransparency ? .labelColor : .white
            }
            layer?.borderColor = (
                reduceTransparency
                    ? NSColor.separatorColor
                    : NSColor.white.withAlphaComponent(0.16)
            ).cgColor
            CATransaction.commit()
        }
    }
}

/// Compact, pointer-transparent status for the ready video surface. It avoids
/// nonessential animation entirely, so Reduce Motion users receive the exact
/// same state changes without fades or pulses.
final class ReadyStatusOverlayView: NSView {
    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private let frameBadge = StatusBadgeView(
        identifier: "status-frame",
        accessibilityLabel: "Current frame status"
    )
    private let zoomBadge = StatusBadgeView(
        identifier: "status-zoom",
        accessibilityLabel: "Zoom status"
    )
    private let lockBadge = StatusBadgeView(
        identifier: "status-lock",
        accessibilityLabel: "Overlay lock status"
    )
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("status-overlay")
        // Keep the container transparent to accessibility so its three
        // explicitly labelled status children remain individually reachable.
        setAccessibilityElement(false)

        let stack = NSStackView(views: [frameBadge, zoomBadge, lockBadge])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.frameBadge.refreshAppearance()
            self?.zoomBadge.refreshAppearance()
            self?.lockBadge.refreshAppearance()
        }
    }

    func update(_ snapshot: ReadyStatusOverlaySnapshot) {
        frameBadge.update(text: snapshot.frameText)
        zoomBadge.update(text: snapshot.zoomText)
        lockBadge.update(text: snapshot.lockText, accent: snapshot.isLocked)
    }

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        Publishers.CombineLatest4(
            state.$currentFrame,
            state.$totalFrames,
            state.$zoomScale,
            state.$isLocked
        )
            .map { currentFrame, totalFrames, zoomScale, isLocked in
                ReadyStatusOverlaySnapshot(
                    currentFrame: currentFrame,
                    totalFrames: totalFrames,
                    zoomScale: zoomScale,
                    isLocked: isLocked
                )
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.update(snapshot)
            }
            .store(in: &cancellables)
    }
}

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

    static let controlBarHeight = ControlBar.regularHeight

    let videoState: VideoState
    private let videoContainerView = NSView()
    private(set) var controlBar: ControlBar!
    private var controlBarHeightConstraint: NSLayoutConstraint!
    private var videoView: VideoView!
    private var dropZoneView: DropZoneView!
    private var edgeIndicatorView: EdgeIndicatorView!
    private var loadingView: NSStackView!
    private var loadingLabel: NSTextField!
    private var errorView: NSStackView!
    private var errorLabel: NSTextField!
    private var retryButton: NSButton!
    private var filterErrorLabel: NSTextField!
    private var statusOverlayView: ReadyStatusOverlayView!
    private var presentationState: MainPresentationState = .empty
    private var cancellables = Set<AnyCancellable>()
    private var filterErrorAnnouncementTracker = AccessibilityErrorAnnouncementTracker()

    weak var windowToDrag: NSWindow? {
        didSet {
            controlBar?.windowToDrag = windowToDrag
        }
    }

    /// Forwarded to the control bar so AppDelegate can own guarded lock entry.
    var onToggleLockRequest: (() -> Void)? {
        didSet {
            controlBar?.onToggleLockRequest = onToggleLockRequest
        }
    }

    /// Reports regular/compact row-height changes. The outer window frame stays
    /// exactly where macOS or Mosaic placed it; the integral video area absorbs
    /// the control-bar height change inside that canonical window.
    var onControlBarPreferredHeightChange: ((CGFloat) -> Void)? {
        didSet {
            if let controlBar {
                onControlBarPreferredHeightChange?(controlBar.preferredHeight)
            }
        }
    }

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
        view.setAccessibilityIdentifier("overlay-content")
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true

        videoContainerView.translatesAutoresizingMaskIntoConstraints = false
        videoContainerView.wantsLayer = true
        videoContainerView.layer?.backgroundColor = .clear
        videoContainerView.setAccessibilityIdentifier("video-container")
        view.addSubview(videoContainerView)

        controlBar = ControlBar(
            frame: NSRect(
                x: 0,
                y: 0,
                width: ControlBar.preferredFullWidth,
                height: Self.controlBarHeight
            )
        )
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.videoState = videoState
        controlBar.windowToDrag = windowToDrag
        controlBar.setAccessibilityIdentifier("control-bar")
        view.addSubview(controlBar)

        controlBarHeightConstraint = controlBar.heightAnchor.constraint(
            equalToConstant: Self.controlBarHeight
        )
        NSLayoutConstraint.activate([
            videoContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            videoContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoContainerView.bottomAnchor.constraint(equalTo: controlBar.topAnchor),

            controlBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlBarHeightConstraint
        ])

        controlBar.onToggleLockRequest = onToggleLockRequest
        controlBar.onPreferredHeightChange = { [weak self] height in
            guard let self else { return }
            if abs(self.controlBarHeightConstraint.constant - height) > 0.5 {
                self.controlBarHeightConstraint.constant = height
            }
            self.onControlBarPreferredHeightChange?(height)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Create views programmatically
        videoView = VideoView()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.setAccessibilityIdentifier("video-view")
        videoContainerView.addSubview(videoView)

        dropZoneView = DropZoneView()
        dropZoneView.translatesAutoresizingMaskIntoConstraints = false
        dropZoneView.setAccessibilityIdentifier("drop-zone")
        videoContainerView.addSubview(dropZoneView)

        loadingView = makeLoadingView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        videoContainerView.addSubview(loadingView)

        errorView = makeErrorView()
        errorView.translatesAutoresizingMaskIntoConstraints = false
        videoContainerView.addSubview(errorView)

        filterErrorLabel = NSTextField(wrappingLabelWithString: "")
        filterErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        filterErrorLabel.alignment = .center
        filterErrorLabel.textColor = .systemRed
        filterErrorLabel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88)
        filterErrorLabel.drawsBackground = true
        filterErrorLabel.setAccessibilityIdentifier("filter-error")
        filterErrorLabel.setAccessibilityRole(.staticText)
        filterErrorLabel.isHidden = true
        videoContainerView.addSubview(filterErrorLabel)

        // Edge indicator view for resize hints (pulsing edges when unlocked)
        edgeIndicatorView = EdgeIndicatorView()
        edgeIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        videoContainerView.addSubview(edgeIndicatorView)

        statusOverlayView = ReadyStatusOverlayView()
        videoContainerView.addSubview(statusOverlayView)

        // Configure views
        videoView.videoState = videoState
        dropZoneView.videoState = videoState
        edgeIndicatorView.videoState = videoState
        statusOverlayView.videoState = videoState

        // Video content fills the area above the integral control bar.
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            dropZoneView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            dropZoneView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            dropZoneView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            dropZoneView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            loadingView.centerXAnchor.constraint(equalTo: videoContainerView.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: videoContainerView.centerYAnchor),
            loadingView.leadingAnchor.constraint(
                greaterThanOrEqualTo: videoContainerView.leadingAnchor,
                constant: 24
            ),
            loadingView.trailingAnchor.constraint(
                lessThanOrEqualTo: videoContainerView.trailingAnchor,
                constant: -24
            ),

            errorView.centerXAnchor.constraint(equalTo: videoContainerView.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: videoContainerView.centerYAnchor),
            errorView.leadingAnchor.constraint(
                greaterThanOrEqualTo: videoContainerView.leadingAnchor,
                constant: 24
            ),
            errorView.trailingAnchor.constraint(
                lessThanOrEqualTo: videoContainerView.trailingAnchor,
                constant: -24
            ),

            filterErrorLabel.topAnchor.constraint(
                equalTo: videoContainerView.topAnchor,
                constant: 12
            ),
            filterErrorLabel.centerXAnchor.constraint(equalTo: videoContainerView.centerXAnchor),
            filterErrorLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: videoContainerView.leadingAnchor,
                constant: 16
            ),
            filterErrorLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: videoContainerView.trailingAnchor,
                constant: -16
            ),

            edgeIndicatorView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            edgeIndicatorView.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor),
            edgeIndicatorView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor),
            edgeIndicatorView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            statusOverlayView.topAnchor.constraint(
                equalTo: videoContainerView.topAnchor,
                constant: 12
            ),
            statusOverlayView.leadingAnchor.constraint(
                equalTo: videoContainerView.leadingAnchor,
                constant: 12
            ),
            statusOverlayView.trailingAnchor.constraint(
                lessThanOrEqualTo: videoContainerView.trailingAnchor,
                constant: -12
            )
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
                guard let self, let filterErrorLabel = self.filterErrorLabel else { return }
                filterErrorLabel.stringValue = message ?? ""
                filterErrorLabel.isHidden = message == nil
                if let announcement = self.filterErrorAnnouncementTracker
                    .newMessageToAnnounce(message) {
                    postAccessibilityErrorAnnouncement(
                        announcement,
                        from: filterErrorLabel
                    )
                }
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

        loadingLabel = NSTextField(labelWithString: "Loading video…")
        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textColor = .secondaryLabelColor

        let cancelButton = NSButton(
            title: "Cancel",
            target: self,
            action: #selector(cancelLoading)
        )
        cancelButton.setAccessibilityIdentifier("button-cancel-loading")
        cancelButton.setAccessibilityHelp("Stop loading and return to the empty state")

        let stack = NSStackView(views: [spinner, loadingLabel, cancelButton])
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
        statusOverlayView.isHidden = state != .ready

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

        if state == .loading {
            if let name = videoState.videoURL?.lastPathComponent, !name.isEmpty {
                loadingLabel.stringValue = "Loading \(name)…"
                loadingView.setAccessibilityHelp("Loading \(name)")
            } else {
                loadingLabel.stringValue = "Loading video…"
                loadingView.setAccessibilityHelp(nil)
            }
        }
    }

    @objc private func retryVideo(_ sender: Any?) {
        videoState.reloadVideo()
    }

    @objc private func chooseAnotherVideo(_ sender: Any?) {
        NotificationCenter.default.post(name: .openVideo, object: nil)
    }

    @objc private func cancelLoading(_ sender: Any?) {
        videoState.videoURL = nil
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
}
