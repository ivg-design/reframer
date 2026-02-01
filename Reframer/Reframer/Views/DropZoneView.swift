import Cocoa
import UniformTypeIdentifiers

/// Pure AppKit drop zone view for video files
class DropZoneView: NSView {

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

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        // Register for drag and drop
        registerForDraggedTypes(VideoFormats.supportedTypes.map { NSPasteboard.PasteboardType($0.identifier) })

        // Glass background
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)

        // Icon
        let icon = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: "Video")
        iconImageView.image = icon
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

        if isTargeted {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    // MARK: - Click Handling

    @objc private func handleClick() {
        NotificationCenter.default.post(name: .openVideo, object: nil)
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

        guard let pasteboard = sender.draggingPasteboard.propertyList(forType: .fileURL) as? String,
              let url = URL(string: pasteboard) else {
            // Try alternative method
            if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let url = urls.first {
                return loadVideo(from: url)
            }
            return false
        }

        return loadVideo(from: url)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    // MARK: - Helpers

    private func hasValidVideoFile(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // Check for file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if VideoFormats.isSupported(url) {
                    return true
                }
            }
        }

        return false
    }

    private func loadVideo(from url: URL) -> Bool {
        guard VideoFormats.isSupported(url) else { return false }

        videoState?.videoURL = url
        videoState?.isVideoLoaded = true
        return true
    }
}
