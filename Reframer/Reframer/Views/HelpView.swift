import Cocoa
import Combine
import ApplicationServices

/// Keyboard shortcut settings presented in a floating AppKit panel.
final class HelpView: NSView {
    private weak var videoState: VideoState?
    private let shortcutSettings: ShortcutSettings
    private let visualEffectView = NSVisualEffectView()
    private let closeButton = NSButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let globalShortcutsButton = NSButton(
        checkboxWithTitle: "Enable global shortcuts",
        target: nil,
        action: nil
    )
    private let permissionButton = NSButton()
    private var cancellables = Set<AnyCancellable>()

    private var shortcutButtons: [ShortcutSettings.Action: NSButton] = [:]
    private var enableButtons: [ShortcutSettings.Action: NSButton] = [:]
    private var clearButtons: [ShortcutSettings.Action: NSButton] = [:]
    private var multiplierButtons: [ShortcutSettings.Action: NSPopUpButton] = [:]

    init(videoState: VideoState) {
        self.videoState = videoState
        self.shortcutSettings = videoState.shortcutSettings
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 640))
        setup()
        observeSettings()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var preferredInitialFirstResponder: NSView {
        closeButton
    }

    private func observeSettings() {
        shortcutSettings.$bindings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateControls() }
            .store(in: &cancellables)

        shortcutSettings.$recordingAction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateControls() }
            .store(in: &cancellables)

        shortcutSettings.$globalShortcutsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateGlobalControls() }
            .store(in: &cancellables)

        shortcutSettings.$validationMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatus() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateGlobalControls() }
            .store(in: &cancellables)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        setAccessibilityIdentifier("modal-help")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Shortcut Settings")
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .followsWindowActiveState
        visualEffectView.setAccessibilityElement(false)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)

        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Shortcut Settings")
        titleLabel.font = .boldSystemFont(ofSize: 15)

        let closeImage = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: nil
        ) ?? NSImage(named: NSImage.stopProgressTemplateName)!
        closeButton.image = closeImage
        closeButton.target = self
        closeButton.action = #selector(closeHelp)
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setAccessibilityElement(true)
        closeButton.setAccessibilityRole(.button)
        closeButton.setAccessibilityIdentifier("help-close")
        closeButton.setAccessibilityLabel("Close Shortcut Settings")
        closeButton.setAccessibilityHelp("Close this panel and return to the previous control")
        closeButton.toolTip = "Close Shortcut Settings"

        headerStack.addArrangedSubview(titleLabel)
        let headerSpacer = NSView()
        headerSpacer.setAccessibilityElement(false)
        headerStack.addArrangedSubview(headerSpacer)
        headerStack.addArrangedSubview(closeButton)
        addSubview(headerStack)

        let infoBanner = makeInfoBanner()
        infoBanner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoBanner)

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

        contentView.addArrangedSubview(makeSection(title: "PLAYBACK", shortcuts: [
            .configurable(.playPause),
            .configurable(.frameStepForward),
            .configurable(.frameStepBackward)
        ]))
        contentView.addArrangedSubview(makeSection(title: "PAN", shortcuts: [
            .configurable(.panLeft),
            .configurable(.panRight),
            .configurable(.panUp),
            .configurable(.panDown)
        ]))
        contentView.addArrangedSubview(makeSection(title: "ZOOM & VIEW", shortcuts: [
            .static("⇧ Scroll", "Zoom 5%"),
            .static("⌘⇧ Scroll", "Fine zoom 0.1%"),
            .configurable(.resetZoom),
            .configurable(.resetView)
        ]))
        contentView.addArrangedSubview(makeSection(title: "WINDOW & PANELS", shortcuts: [
            .configurable(.toggleLock),
            .configurable(.globalToggleLock),
            .configurable(.showHelp),
            .configurable(.closeModal),
            .configurable(.toggleFilterPanel)
        ]))
        contentView.addArrangedSubview(makeSection(title: "POINTER", shortcuts: [
            .static("Drag video", "Pan video"),
            .static("Drag grip", "Move window"),
            .static("Drag edges", "Resize window")
        ]))

        scrollView.documentView = contentView
        addSubview(scrollView)

        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        footerStack.distribution = .fill
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(
            title: "Reset All to Defaults",
            target: self,
            action: #selector(resetShortcuts)
        )
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.setAccessibilityHelp("Restores every shortcut and multiplier.")

        globalShortcutsButton.target = self
        globalShortcutsButton.action = #selector(globalShortcutsChanged(_:))
        globalShortcutsButton.controlSize = .small
        globalShortcutsButton.setAccessibilityHelp(
            "Allows lock and frame-step shortcuts to work from other applications."
        )

        permissionButton.title = "Grant Accessibility Access…"
        permissionButton.target = self
        permissionButton.action = #selector(requestAccessibilityAccess(_:))
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small

        footerStack.addArrangedSubview(resetButton)
        footerStack.addArrangedSubview(globalShortcutsButton)
        footerStack.addArrangedSubview(NSView())
        footerStack.addArrangedSubview(permissionButton)
        addSubview(footerStack)

        let topDivider = NSBox()
        topDivider.boxType = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        let bottomDivider = NSBox()
        bottomDivider.boxType = .separator
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomDivider)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

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

            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        updateStatus()
        updateControls()
        updateGlobalControls()
    }

    private func makeInfoBanner() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setAccessibilityIdentifier("shortcut-validation-status")
        statusLabel.setAccessibilityRole(.staticText)
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10)
        ])
        return container
    }

    private enum ShortcutType {
        case `static`(String, String)
        case configurable(ShortcutSettings.Action)
    }

    private func makeSection(title: String, shortcuts: [ShortcutType]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(titleLabel)

        shortcuts.forEach { stack.addArrangedSubview(makeShortcutRow($0)) }
        return stack
    }

    private func makeShortcutRow(_ shortcutType: ShortcutType) -> NSView {
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

        let keysLabel = NSTextField(labelWithString: keys)
        keysLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        keysLabel.alignment = .center
        keysLabel.wantsLayer = true
        keysLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        keysLabel.layer?.cornerRadius = 4
        keysLabel.translatesAutoresizingMaskIntoConstraints = false
        keysLabel.widthAnchor.constraint(equalToConstant: 105).isActive = true

        let descriptionLabel = NSTextField(labelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 18, height: 1)))
        stack.addArrangedSubview(keysLabel)
        stack.addArrangedSubview(descriptionLabel)
        return stack
    }

    private func makeConfigurableRow(action: ShortcutSettings.Action) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7

        let enableButton = NSButton(
            checkboxWithTitle: "",
            target: self,
            action: #selector(enabledChanged(_:))
        )
        enableButton.toolTip = "Enable \(action.displayName)"
        enableButton.setAccessibilityLabel("Enable \(action.displayName)")
        enableButtons[action] = enableButton

        let shortcutButton = NSButton(
            title: shortcutSettings.displayString(for: action),
            target: self,
            action: #selector(shortcutButtonClicked(_:))
        )
        shortcutButton.bezelStyle = .inline
        shortcutButton.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        shortcutButton.wantsLayer = true
        shortcutButton.layer?.cornerRadius = 4
        shortcutButton.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        shortcutButton.contentTintColor = .labelColor
        shortcutButton.toolTip = "Record a new shortcut for \(action.displayName)"
        shortcutButton.setAccessibilityLabel("\(action.displayName) shortcut")
        shortcutButton.translatesAutoresizingMaskIntoConstraints = false
        shortcutButton.widthAnchor.constraint(equalToConstant: 105).isActive = true
        shortcutButtons[action] = shortcutButton

        var description = action.displayName
        if action.isGlobal {
            description += " (global)"
        }
        let descriptionLabel = NSTextField(labelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(enableButton)
        stack.addArrangedSubview(shortcutButton)
        stack.addArrangedSubview(descriptionLabel)

        if action.hasMultiplierVariant {
            let popup = makeMultiplierDropdown(action: action)
            stack.addArrangedSubview(popup)
        } else {
            let spacer = NSView(frame: NSRect(x: 0, y: 0, width: 112, height: 1))
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.widthAnchor.constraint(equalToConstant: 112).isActive = true
            stack.addArrangedSubview(spacer)
        }

        let clearButton = NSButton(
            title: "Clear",
            target: self,
            action: #selector(clearShortcut(_:))
        )
        clearButton.bezelStyle = .inline
        clearButton.controlSize = .small
        clearButton.toolTip = "Clear \(action.displayName)"
        clearButton.setAccessibilityLabel("Clear \(action.displayName) shortcut")
        clearButtons[action] = clearButton
        stack.addArrangedSubview(clearButton)

        return stack
    }

    private func makeMultiplierDropdown(action: ShortcutSettings.Action) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = .systemFont(ofSize: 11)
        popup.controlSize = .small

        for (_, symbol, _) in ShortcutSettings.availableMultiplierModifiers {
            if action.hasHundredVariant {
                popup.addItem(withTitle: "\(symbol) 10× · ⌘\(symbol) 100×")
            } else {
                popup.addItem(withTitle: "\(symbol) 10×")
            }
        }
        popup.target = self
        popup.action = #selector(multiplierChanged(_:))
        popup.toolTip = "Choose the 10× multiplier modifier"
        popup.setAccessibilityLabel("\(action.displayName) multiplier")
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 112).isActive = true
        multiplierButtons[action] = popup
        return popup
    }

    private func updateControls() {
        for action in ShortcutSettings.Action.allCases {
            let binding = shortcutSettings.binding(for: action)
            let isRecording = shortcutSettings.recordingAction == action

            if let button = shortcutButtons[action] {
                button.title = isRecording
                    ? "Press shortcut…"
                    : shortcutSettings.displayString(for: action)
                button.isEnabled = binding.isEnabled
                button.layer?.borderWidth = isRecording ? 2 : 0
                button.layer?.borderColor = isRecording
                    ? NSColor.controlAccentColor.cgColor
                    : nil
                button.layer?.removeAnimation(forKey: "shortcut-recording-pulse")
                if isRecording && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    let animation = CABasicAnimation(keyPath: "borderColor")
                    animation.fromValue = NSColor.controlAccentColor.cgColor
                    animation.toValue = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                    animation.duration = 0.5
                    animation.autoreverses = true
                    animation.repeatCount = .infinity
                    button.layer?.add(animation, forKey: "shortcut-recording-pulse")
                }
            }

            enableButtons[action]?.state = binding.isEnabled ? .on : .off
            clearButtons[action]?.isEnabled = binding.shortcut != nil
            multiplierButtons[action]?.isEnabled = binding.isEnabled && binding.shortcut != nil

            if let shortcut = binding.shortcut,
               let popup = multiplierButtons[action] {
                let modifier = NSEvent.ModifierFlags(rawValue: shortcut.multiplierModifier)
                if let index = ShortcutSettings.availableMultiplierModifiers.firstIndex(
                    where: { $0.flags == modifier }
                ) {
                    popup.selectItem(at: index)
                }
            }
        }
        updateStatus()
    }

    private func updateStatus() {
        if let message = shortcutSettings.validationMessage {
            statusLabel.stringValue = message
            statusLabel.textColor = .systemRed
            statusLabel.superview?.layer?.backgroundColor =
                NSColor.systemRed.withAlphaComponent(0.13).cgColor
            statusLabel.setAccessibilityLabel("Shortcut error: \(message)")
        } else if let action = shortcutSettings.recordingAction {
            statusLabel.stringValue =
                "Press the new shortcut for \(action.displayName). Escape cancels; Delete clears it."
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.superview?.layer?.backgroundColor =
                NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            statusLabel.setAccessibilityLabel(statusLabel.stringValue)
        } else {
            statusLabel.stringValue =
                "Shortcuts are validated for duplicates and unsafe global keys. Disable preserves a chord; Clear removes it."
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.superview?.layer?.backgroundColor =
                NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            statusLabel.setAccessibilityLabel(statusLabel.stringValue)
        }
    }

    private func updateGlobalControls() {
        globalShortcutsButton.state = shortcutSettings.globalShortcutsEnabled ? .on : .off
        let trusted = AXIsProcessTrusted()
        permissionButton.title = trusted
            ? "Accessibility Access Granted"
            : "Grant Accessibility Access…"
        permissionButton.isEnabled = !trusted && shortcutSettings.globalShortcutsEnabled
        permissionButton.setAccessibilityValue(trusted ? "Granted" : "Not granted")
    }

    @objc private func closeHelp() {
        shortcutSettings.cancelRecording()
        videoState?.showHelp = false
    }

    @objc private func resetShortcuts() {
        shortcutSettings.resetToDefaults()
    }

    @objc private func globalShortcutsChanged(_ sender: NSButton) {
        shortcutSettings.setGlobalShortcutsEnabled(sender.state == .on)
        updateGlobalControls()
    }

    @objc private func requestAccessibilityAccess(_ sender: NSButton) {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(settingsURL)
        }
        NotificationCenter.default.post(
            name: .reconfigureGlobalShortcutMonitor,
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.updateGlobalControls()
        }
    }

    @objc private func shortcutButtonClicked(_ sender: NSButton) {
        guard let action = shortcutButtons.first(where: { $0.value === sender })?.key else {
            return
        }
        if shortcutSettings.recordingAction == action {
            shortcutSettings.cancelRecording()
        } else {
            shortcutSettings.beginRecording(for: action)
        }
    }

    @objc private func enabledChanged(_ sender: NSButton) {
        guard let action = enableButtons.first(where: { $0.value === sender })?.key else {
            return
        }
        if case .failure = shortcutSettings.setEnabled(sender.state == .on, for: action) {
            sender.state = shortcutSettings.binding(for: action).isEnabled ? .on : .off
            NSSound.beep()
        }
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        guard let action = clearButtons.first(where: { $0.value === sender })?.key else {
            return
        }
        shortcutSettings.clearShortcut(for: action)
    }

    @objc private func multiplierChanged(_ sender: NSPopUpButton) {
        guard let action = multiplierButtons.first(where: { $0.value === sender })?.key else {
            return
        }
        let index = sender.indexOfSelectedItem
        guard ShortcutSettings.availableMultiplierModifiers.indices.contains(index) else {
            return
        }
        let modifier = ShortcutSettings.availableMultiplierModifiers[index].flags
        if case .failure = shortcutSettings.setMultiplierModifier(modifier, for: action) {
            NSSound.beep()
            updateControls()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 520, height: 640)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            shortcutSettings.cancelRecording()
        }
    }

    deinit {
        shortcutSettings.cancelRecording()
    }
}
