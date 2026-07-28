import Cocoa
import UniformTypeIdentifiers

/// Pure AppKit drop zone view for video files
class DropZoneView: NSView, ReframerShortcutOwningResponder {

    // MARK: - Properties

    weak var videoState: VideoState?
    private var isTargeted = false {
        didSet { needsDisplay = true }
    }

    private let visualEffectView = NSVisualEffectView()
    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Drop video here")
    private let subtitleLabel = NSTextField(labelWithString: "or press ⌘O to open")
    private let formatsLabel = NSTextField(labelWithString: VideoFormats.displayString)

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        focusRingType = .exterior

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open video")
        setAccessibilityHelp("Open or drop an MP4, M4V, or MOV video")
        setAccessibilityIdentifier("open-video-drop-zone")
        setAccessibilityEnabled(true)

        // Register for drag and drop - must register for fileURL to accept file drops
        registerForDraggedTypes([.fileURL])

        // Glass background with strong blur
        visualEffectView.material = .fullScreenUI
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)

        // Icon
        let icon = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: "Video")
        iconImageView.image = icon
        iconImageView.setAccessibilityElement(false)
        iconImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .light)
        iconImageView.contentTintColor = .secondaryLabelColor
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconImageView)

        // Title
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        // Formats
        formatsLabel.font = NSFont.systemFont(ofSize: 11)
        formatsLabel.textColor = .tertiaryLabelColor
        formatsLabel.alignment = .center
        formatsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatsLabel)

        // Layout
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            formatsLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            formatsLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])

        // Click gesture
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isTargeted || window?.firstResponder === self {
            // The composite window owns its outer corner clipping. Keeping the
            // drop zone rectangular prevents an artificial rounded gap where
            // the video surface meets the integral control bar.
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    // MARK: - Click Handling

    @objc private func handleClick() {
        activateOpen()
    }

    private func activateOpen() {
        NotificationCenter.default.post(name: .openVideo, object: nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76: // Return, Space, keypad Enter
            activateOpen()
        default:
            super.keyDown(with: event)
        }
    }

    func ownsReframerShortcut(_ stroke: ShortcutKeystroke) -> Bool {
        stroke.modifiers == 0 && [36, 49, 76].contains(stroke.keyCode)
    }

    override func accessibilityPerformPress() -> Bool {
        activateOpen()
        return true
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasValidVideoFile(sender) {
            isTargeted = true
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return hasValidVideoFile(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return hasValidVideoFile(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false

        guard let url = supportedVideoURL(in: sender) else { return false }
        return loadVideo(from: url)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    // MARK: - Helpers

    private func hasValidVideoFile(_ sender: NSDraggingInfo) -> Bool {
        supportedVideoURL(in: sender) != nil
    }

    private func supportedVideoURL(in sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        return Self.firstSupportedVideoURL(in: urls)
    }

    static func firstSupportedVideoURL(in urls: [URL]) -> URL? {
        urls.first(where: VideoFormats.isSupported)
    }

    func loadVideo(from url: URL) -> Bool {
        guard VideoFormats.isSupported(url) else { return false }

        videoState?.isVideoLoaded = false
        videoState?.videoURL = url
        return true
    }
}
