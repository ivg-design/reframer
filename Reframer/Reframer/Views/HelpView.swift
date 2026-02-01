import Cocoa
import Combine

/// Pure AppKit help modal view
class HelpView: NSView {

    private weak var videoState: VideoState?
    private let visualEffectView = NSVisualEffectView()

    init(videoState: VideoState) {
        self.videoState = videoState
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 480))
        setup()
    }

    required init?(coder: NSCoder) {
        // This view must be initialized programmatically with a VideoState
        return nil
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        setAccessibilityIdentifier("modal-help")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        // Glass background
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Header
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Keyboard Shortcuts")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)

        let closeImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") ?? NSImage(named: NSImage.stopProgressTemplateName)!
        let closeButton = NSButton(image: closeImage, target: self, action: #selector(closeHelp))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(NSView()) // Spacer
        headerStack.addArrangedSubview(closeButton)
        addSubview(headerStack)

        // Scroll view for content
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSStackView()
        contentView.orientation = .vertical
        contentView.alignment = .leading
        contentView.spacing = 16
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        // Add shortcut sections
        contentView.addArrangedSubview(makeSection(title: "FILE", shortcuts: [
            ("⌘O", "Open video file")
        ]))

        contentView.addArrangedSubview(makeSection(title: "PLAYBACK", shortcuts: [
            ("Space", "Play / Pause"),
            ("Scroll", "Step frames (unlocked)"),
            ("⌘ PgUp/Dn", "Step frame (global, ⇧ for 10, lock mode)")
        ]))

        contentView.addArrangedSubview(makeSection(title: "PAN (ARROWS)", shortcuts: [
            ("← → ↑ ↓", "Pan 1px (unlocked)"),
            ("⇧ Arrows", "Pan 10px"),
            ("⇧⌘ Arrows", "Pan 100px")
        ]))

        contentView.addArrangedSubview(makeSection(title: "ZOOM", shortcuts: [
            ("⇧ Scroll", "Zoom 5% (unlocked)"),
            ("⌘⇧ Scroll", "Fine zoom 0.1%"),
            ("0", "Reset zoom to 100%"),
            ("R", "Reset zoom and pan")
        ]))

        contentView.addArrangedSubview(makeSection(title: "WINDOW & LOCK", shortcuts: [
            ("L", "Toggle lock mode"),
            ("⌘⇧L", "Toggle lock (global)"),
            ("H / ?", "Show this help"),
            ("Esc", "Close help")
        ]))

        contentView.addArrangedSubview(makeSection(title: "MOUSE", shortcuts: [
            ("Ctrl+Drag", "Pan video (unlocked)"),
            ("Drag bar", "Move window"),
            ("Drag edges", "Resize window (unlocked)")
        ]))

        contentView.addArrangedSubview(makeSection(title: "INPUTS", shortcuts: [
            ("↑ / ↓", "Step value (⇧ for 10, ⌘ for 0.1% zoom)"),
            ("⌘A", "Select all"),
            ("Esc / Enter", "Defocus")
        ]))

        scrollView.documentView = contentView
        addSubview(scrollView)

        // Footer
        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        footerStack.distribution = .fill
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let appLabel = NSTextField(labelWithString: "Video Overlay")
        appLabel.font = NSFont.systemFont(ofSize: 11)
        appLabel.textColor = .secondaryLabelColor

        let escLabel = NSTextField(labelWithString: "Press Esc to close")
        escLabel.font = NSFont.systemFont(ofSize: 11)
        escLabel.textColor = .tertiaryLabelColor

        footerStack.addArrangedSubview(appLabel)
        footerStack.addArrangedSubview(NSView()) // Spacer
        footerStack.addArrangedSubview(escLabel)
        addSubview(footerStack)

        // Dividers
        let topDivider = NSBox()
        topDivider.boxType = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomDivider)

        // Layout
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            topDivider.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomDivider.topAnchor),

            bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -8),

            footerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }

    private func makeSection(title: String, shortcuts: [(String, String)]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(titleLabel)

        for (keys, description) in shortcuts {
            let row = makeShortcutRow(keys: keys, description: description)
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func makeShortcutRow(keys: String, description: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8

        let keysLabel = NSTextField(labelWithString: keys)
        keysLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        keysLabel.wantsLayer = true
        keysLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        keysLabel.layer?.cornerRadius = 4

        let keysContainer = NSView()
        keysContainer.wantsLayer = true
        keysContainer.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        keysContainer.layer?.cornerRadius = 4
        keysContainer.addSubview(keysLabel)
        keysLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            keysLabel.topAnchor.constraint(equalTo: keysContainer.topAnchor, constant: 2),
            keysLabel.bottomAnchor.constraint(equalTo: keysContainer.bottomAnchor, constant: -2),
            keysLabel.leadingAnchor.constraint(equalTo: keysContainer.leadingAnchor, constant: 6),
            keysLabel.trailingAnchor.constraint(equalTo: keysContainer.trailingAnchor, constant: -6),
            keysContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(keysContainer)
        stack.addArrangedSubview(descLabel)

        return stack
    }

    @objc private func closeHelp() {
        videoState?.showHelp = false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 340, height: 480)
    }
}
