import Cocoa
import Combine

/// Pure AppKit help modal view with configurable shortcuts
class HelpView: NSView {

    private weak var videoState: VideoState?
    private let visualEffectView = NSVisualEffectView()
    private var shortcutSettings: ShortcutSettings
    private var cancellables = Set<AnyCancellable>()

    // Recording state
    private var recordingAction: ShortcutSettings.Action?
    private var recordingButton: NSButton?
    private var localEventMonitor: Any?

    // Configurable shortcut buttons (keyed by action)
    private var shortcutButtons: [ShortcutSettings.Action: NSButton] = [:]

    // Multiplier modifier buttons (keyed by action)
    private var multiplierButtons: [ShortcutSettings.Action: NSPopUpButton] = [:]

    init(videoState: VideoState) {
        self.videoState = videoState
        self.shortcutSettings = videoState.shortcutSettings
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 580))
        setup()
        observeSettings()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func observeSettings() {
        shortcutSettings.$shortcuts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateShortcutLabels()
            }
            .store(in: &cancellables)
    }

    private func updateShortcutLabels() {
        for (action, button) in shortcutButtons {
            let displayString = shortcutSettings.displayString(for: action)
            button.title = displayString
        }
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

        // Info banner
        let infoBanner = makeInfoBanner()
        addSubview(infoBanner)

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
        contentView.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)

        // Add shortcut sections - all configurable now
        contentView.addArrangedSubview(makeSection(title: "PLAYBACK", shortcuts: [
            .configurable(.playPause),
            .configurable(.frameStepForward),
            .configurable(.frameStepBackward),
        ]))

        contentView.addArrangedSubview(makeSection(title: "PAN", shortcuts: [
            .configurable(.panLeft),
            .configurable(.panRight),
            .configurable(.panUp),
            .configurable(.panDown),
        ]))

        contentView.addArrangedSubview(makeSection(title: "ZOOM & VIEW", shortcuts: [
            .static("⇧ Scroll", "Zoom 5%"),
            .static("⌘⇧ Scroll", "Fine zoom 0.1%"),
            .configurable(.resetZoom),
            .configurable(.resetView),
        ]))

        contentView.addArrangedSubview(makeSection(title: "WINDOW & LOCK", shortcuts: [
            .configurable(.toggleLock),
            .configurable(.globalToggleLock),
            .configurable(.showHelp),
            .configurable(.closeModal),
            .configurable(.toggleFilterPanel),
        ]))

        contentView.addArrangedSubview(makeSection(title: "MOUSE", shortcuts: [
            .static("Ctrl+Drag", "Pan video"),
            .static("Drag window", "Move window"),
            .static("Drag edges", "Resize window"),
        ]))

        scrollView.documentView = contentView
        addSubview(scrollView)

        // Footer with Reset button
        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        footerStack.distribution = .fill
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetShortcuts))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small

        let escLabel = NSTextField(labelWithString: "Press Esc to close")
        escLabel.font = NSFont.systemFont(ofSize: 11)
        escLabel.textColor = .tertiaryLabelColor

        footerStack.addArrangedSubview(resetButton)
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
        infoBanner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            infoBanner.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            infoBanner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            infoBanner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            topDivider.topAnchor.constraint(equalTo: infoBanner.bottomAnchor, constant: 12),
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

    // MARK: - Info Banner

    private func makeInfoBanner() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        container.layer?.cornerRadius = 6

        let label = NSTextField(wrappingLabelWithString: "Click any shortcut to change it. Be mindful of conflicts with other shortcuts or apps.")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        ])

        return container
    }

    // MARK: - Shortcut Types

    private enum ShortcutType {
        case `static`(String, String)  // keys, description
        case configurable(ShortcutSettings.Action)
    }

    private func makeSection(title: String, shortcuts: [ShortcutType]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(titleLabel)

        for shortcutType in shortcuts {
            let row = makeShortcutRow(shortcutType: shortcutType)
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func makeShortcutRow(shortcutType: ShortcutType) -> NSView {
        switch shortcutType {
        case .static(let keys, let description):
            return makeStaticRow(keys: keys, description: description)
        case .configurable(let action):
            return makeConfigurableRow(action: action)
        }
    }

    private func makeStaticRow(keys: String, description: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8

        let keysView = makeStaticKeyLabel(keys: keys)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(keysView)
        stack.addArrangedSubview(descLabel)

        return stack
    }

    private func makeConfigurableRow(action: ShortcutSettings.Action) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8

        // Main shortcut button
        let keysView = makeConfigurableKeyButton(action: action)
        stack.addArrangedSubview(keysView)

        // Description
        var descText = action.displayName
        if action.isGlobal {
            descText += " (global)"
        }
        let descLabel = NSTextField(labelWithString: descText)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(descLabel)

        // Multiplier modifier dropdown if applicable
        if action.hasMultiplierVariant {
            let multiplierView = makeMultiplierDropdown(action: action)
            stack.addArrangedSubview(multiplierView)
        }

        return stack
    }

    private func makeStaticKeyLabel(keys: String) -> NSView {
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
            keysContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        return keysContainer
    }

    private func makeConfigurableKeyButton(action: ShortcutSettings.Action) -> NSView {
        let displayString = shortcutSettings.displayString(for: action)

        let button = NSButton(title: displayString, target: self, action: #selector(shortcutButtonClicked(_:)))
        button.bezelStyle = .inline
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        button.contentTintColor = .labelColor
        button.toolTip = "Click to change shortcut"

        // Store reference for updates
        shortcutButtons[action] = button

        // Container with minimum width
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 4
        container.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        container.addSubview(button)

        button.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        return container
    }

    private func makeMultiplierDropdown(action: ShortcutSettings.Action) -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = NSFont.systemFont(ofSize: 11)
        popup.controlSize = .small

        // Add modifier options
        for (_, symbol, _) in ShortcutSettings.availableMultiplierModifiers {
            popup.addItem(withTitle: "\(symbol) 10x")
        }

        // Set current selection
        if let shortcut = shortcutSettings.shortcuts[action] {
            let currentMod = NSEvent.ModifierFlags(rawValue: shortcut.multiplierModifier)
            for (index, (_, _, flags)) in ShortcutSettings.availableMultiplierModifiers.enumerated() {
                if flags == currentMod {
                    popup.selectItem(at: index)
                    break
                }
            }
        }

        popup.target = self
        popup.action = #selector(multiplierChanged(_:))
        multiplierButtons[action] = popup

        popup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            popup.widthAnchor.constraint(equalToConstant: 60)
        ])

        return popup
    }

    // MARK: - Actions

    @objc private func closeHelp() {
        cancelRecording()
        videoState?.showHelp = false
    }

    @objc private func resetShortcuts() {
        shortcutSettings.resetToDefaults()
        // Update multiplier dropdowns
        for (action, popup) in multiplierButtons {
            if let shortcut = shortcutSettings.shortcuts[action] {
                let currentMod = NSEvent.ModifierFlags(rawValue: shortcut.multiplierModifier)
                for (index, (_, _, flags)) in ShortcutSettings.availableMultiplierModifiers.enumerated() {
                    if flags == currentMod {
                        popup.selectItem(at: index)
                        break
                    }
                }
            }
        }
    }

    @objc private func shortcutButtonClicked(_ sender: NSButton) {
        // Find which action this button belongs to
        guard let action = shortcutButtons.first(where: { $0.value === sender })?.key else { return }

        // Cancel any existing recording
        cancelRecording()

        // Start recording for this action
        startRecording(for: action, button: sender)
    }

    @objc private func multiplierChanged(_ sender: NSPopUpButton) {
        // Find which action this popup belongs to
        guard let action = multiplierButtons.first(where: { $0.value === sender })?.key else { return }

        let selectedIndex = sender.indexOfSelectedItem
        guard selectedIndex >= 0 && selectedIndex < ShortcutSettings.availableMultiplierModifiers.count else { return }

        let (_, _, flags) = ShortcutSettings.availableMultiplierModifiers[selectedIndex]
        shortcutSettings.setMultiplierModifier(flags, for: action)
    }

    // MARK: - Recording

    private func startRecording(for action: ShortcutSettings.Action, button: NSButton) {
        recordingAction = action
        recordingButton = button
        videoState?.isRecordingShortcut = true

        // Update button appearance
        button.title = "Press keys..."
        button.layer?.borderWidth = 2
        button.layer?.borderColor = NSColor.controlAccentColor.cgColor

        // Add pulsing animation
        let animation = CABasicAnimation(keyPath: "borderColor")
        animation.fromValue = NSColor.controlAccentColor.cgColor
        animation.toValue = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        button.layer?.add(animation, forKey: "pulse")

        // Start monitoring for key events
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            return self?.handleRecordingEvent(event)
        }
    }

    private func cancelRecording() {
        guard let button = recordingButton, let action = recordingAction else { return }

        // Stop monitoring
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }

        // Restore button appearance
        button.layer?.removeAnimation(forKey: "pulse")
        button.layer?.borderWidth = 0
        button.title = shortcutSettings.displayString(for: action)

        recordingAction = nil
        recordingButton = nil

        // Clear the recording flag on next event cycle so AppDelegate sees it during this event
        DispatchQueue.main.async { [weak self] in
            self?.videoState?.isRecordingShortcut = false
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        guard let action = recordingAction else { return event }

        // Escape cancels recording (but don't close the window)
        if event.keyCode == KeyCode.escape {
            cancelRecording()
            // Return nil to consume the event so it doesn't propagate to close the window
            return nil
        }

        // Ignore pure modifier key presses (wait for actual key)
        if event.type == .flagsChanged {
            return nil
        }

        // Get modifiers - filter to only relevant ones
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let modifiers = event.modifierFlags.intersection(relevantModifiers)

        // Get existing multiplier modifier (preserve it)
        let existingMultiplier = shortcutSettings.shortcuts[action]?.multiplierModifier ?? NSEvent.ModifierFlags.shift.rawValue

        // Create new shortcut
        let newShortcut = ShortcutSettings.Shortcut(
            keyCode: event.keyCode,
            modifiers: modifiers.rawValue,
            multiplierModifier: existingMultiplier
        )

        // Save the shortcut
        shortcutSettings.setShortcut(newShortcut, for: action)

        // End recording
        cancelRecording()

        return nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 380, height: 580)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Cancel recording if window is hidden/closed
        if window == nil {
            cancelRecording()
        }
    }

    deinit {
        cancelRecording()
    }
}
