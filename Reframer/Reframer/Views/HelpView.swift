import Cocoa
import Combine

enum ShortcutSettingsWindowConfiguration {
    static let styleMask: NSWindow.StyleMask = [.borderless, .resizable]
}

/// Keyboard shortcut settings presented in a floating AppKit panel.
final class HelpView: NSView {
    static let minimumWindowSize = NSSize(width: 700, height: 520)
    static let preferredWindowSize = NSSize(width: 780, height: 1_020)
    static let maximumWindowSize = NSSize(width: 1_100, height: 1_100)

    private enum GridColumn: Int, CaseIterable {
        case enabled
        case shortcut
        case action
        case multiplier
        case clear
    }

    private static let gridColumnSpacing: CGFloat = 12
    private static let enabledColumnWidth: CGFloat = 22
    private static let shortcutColumnWidth: CGFloat = 132
    private static let minimumActionColumnWidth: CGFloat = 210
    private static let multiplierColumnWidth: CGFloat = 178
    private static let clearColumnWidth: CGFloat = 60
    private static let contentHorizontalInset: CGFloat = 16

    private weak var videoState: VideoState?
    private let shortcutSettings: ShortcutSettings
    private let visualEffectView = NSVisualEffectView()
    private let closeButton = NSButton()
    private let scrollView = NSScrollView()
    private let shortcutGrid = NSGridView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let globalShortcutsButton = NSButton(
        checkboxWithTitle: "Enable global shortcuts",
        target: nil,
        action: nil
    )
    private let retryRegistrationButton = NSButton()
    private var cancellables = Set<AnyCancellable>()
    private var displayOptionsObserver: NSObjectProtocol?
    private var errorAnnouncementTracker = AccessibilityErrorAnnouncementTracker()

    private var shortcutButtons: [ShortcutSettings.Action: NSButton] = [:]
    private var enableButtons: [ShortcutSettings.Action: NSButton] = [:]
    private var clearButtons: [ShortcutSettings.Action: NSButton] = [:]
    private var multiplierButtons: [ShortcutSettings.Action: NSPopUpButton] = [:]
    private var focusOrder: [NSView] = []

    init(videoState: VideoState) {
        self.videoState = videoState
        self.shortcutSettings = videoState.shortcutSettings
        super.init(frame: NSRect(origin: .zero, size: Self.preferredWindowSize))
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

        shortcutSettings.$globalRegistrationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatus()
                self?.updateGlobalControls()
            }
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
        closeButton.identifier = NSUserInterfaceItemIdentifier("help-close")
        closeButton.setAccessibilityLabel("Close Shortcut Settings")
        closeButton.setAccessibilityHelp("Close this panel and return to the previous control")
        closeButton.toolTip = "Close Shortcut Settings"

        headerStack.addArrangedSubview(titleLabel)
        let headerSpacer = NSView()
        headerSpacer.setAccessibilityElement(false)
        headerStack.addArrangedSubview(headerSpacer)
        headerStack.addArrangedSubview(closeButton)
        addSubview(headerStack)
        focusOrder.append(closeButton)

        let infoBanner = makeInfoBanner()
        infoBanner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoBanner)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setAccessibilityIdentifier("shortcut-scroll")
        scrollView.identifier = NSUserInterfaceItemIdentifier("shortcut-scroll")

        let contentView = NSStackView()
        contentView.orientation = .vertical
        contentView.alignment = .leading
        contentView.spacing = 0
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.edgeInsets = NSEdgeInsets(
            top: 12,
            left: Self.contentHorizontalInset,
            bottom: 16,
            right: Self.contentHorizontalInset
        )

        configureShortcutGrid()
        addSection(title: "PLAYBACK", identifier: "playback", shortcuts: [
            .configurable(.playPause),
            .configurable(.frameStepForward),
            .configurable(.frameStepBackward)
        ])
        addSection(title: "PAN", identifier: "pan", shortcuts: [
            .configurable(.panLeft),
            .configurable(.panRight),
            .configurable(.panUp),
            .configurable(.panDown)
        ])
        addSection(title: "ZOOM & VIEW", identifier: "zoom-view", shortcuts: [
            .static(identifier: "zoom-scroll", keys: "⇧ Scroll", description: "Zoom 5%"),
            .static(
                identifier: "fine-zoom-scroll",
                keys: "⌘⇧ Scroll",
                description: "Fine zoom 0.1%"
            ),
            .configurable(.resetZoom),
            .configurable(.resetView)
        ])
        addSection(title: "WINDOW & PANELS", identifier: "window-panels", shortcuts: [
            .configurable(.toggleLock),
            .configurable(.globalToggleLock),
            .configurable(.showHelp),
            .configurable(.closeModal),
            .configurable(.toggleFilterPanel)
        ])
        addSection(title: "POINTER", identifier: "pointer", shortcuts: [
            .static(identifier: "drag-video", keys: "Drag video", description: "Pan video"),
            .static(identifier: "drag-grip", keys: "Drag grip", description: "Move window"),
            .static(
                identifier: "drag-edges",
                keys: "Drag edges",
                description: "Resize window"
            )
        ])
        configureShortcutGridColumns()

        contentView.addArrangedSubview(shortcutGrid)
        shortcutGrid.widthAnchor.constraint(
            equalTo: contentView.widthAnchor,
            constant: -(Self.contentHorizontalInset * 2)
        ).isActive = true
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
            "Registers only the enabled lock and frame-step chords with macOS. No Accessibility or Input Monitoring permission is required."
        )

        retryRegistrationButton.title = "Retry Global Shortcuts"
        retryRegistrationButton.target = self
        retryRegistrationButton.action = #selector(retryGlobalShortcutRegistration(_:))
        retryRegistrationButton.bezelStyle = .rounded
        retryRegistrationButton.controlSize = .small
        retryRegistrationButton.setAccessibilityLabel("Retry global shortcut registration")
        retryRegistrationButton.setAccessibilityHelp(
            "Try again after changing a conflicting shortcut in Reframer or another app."
        )

        footerStack.addArrangedSubview(resetButton)
        footerStack.addArrangedSubview(globalShortcutsButton)
        footerStack.addArrangedSubview(NSView())
        footerStack.addArrangedSubview(retryRegistrationButton)
        footerStack.setAccessibilityIdentifier("shortcut-footer")
        footerStack.identifier = NSUserInterfaceItemIdentifier("shortcut-footer")
        addSubview(footerStack)
        focusOrder.append(contentsOf: [
            resetButton,
            globalShortcutsButton,
            retryRegistrationButton
        ])

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

        configureFocusLoop()
        updateStatus()
        updateControls()
        updateGlobalControls()
        displayOptionsObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateControls()
        }
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
        case `static`(identifier: String, keys: String, description: String)
        case configurable(ShortcutSettings.Action)
    }

    private func configureShortcutGrid() {
        shortcutGrid.translatesAutoresizingMaskIntoConstraints = false
        shortcutGrid.rowSpacing = 7
        shortcutGrid.columnSpacing = Self.gridColumnSpacing
        shortcutGrid.setAccessibilityIdentifier("shortcut-grid")
        shortcutGrid.identifier = NSUserInterfaceItemIdentifier("shortcut-grid")
    }

    private func configureShortcutGridColumns() {
        guard shortcutGrid.numberOfColumns == GridColumn.allCases.count else {
            return
        }
        shortcutGrid.column(at: GridColumn.enabled.rawValue).width =
            Self.enabledColumnWidth
        shortcutGrid.column(at: GridColumn.enabled.rawValue).xPlacement = .center
        shortcutGrid.column(at: GridColumn.shortcut.rawValue).width =
            Self.shortcutColumnWidth
        shortcutGrid.column(at: GridColumn.shortcut.rawValue).xPlacement = .fill
        shortcutGrid.column(at: GridColumn.action.rawValue).width =
            Self.minimumActionColumnWidth
        shortcutGrid.column(at: GridColumn.action.rawValue).xPlacement = .fill
        shortcutGrid.column(at: GridColumn.multiplier.rawValue).width =
            Self.multiplierColumnWidth
        shortcutGrid.column(at: GridColumn.multiplier.rawValue).xPlacement = .fill
        shortcutGrid.column(at: GridColumn.clear.rawValue).width =
            Self.clearColumnWidth
        shortcutGrid.column(at: GridColumn.clear.rawValue).xPlacement = .leading
    }

    private func addSection(
        title: String,
        identifier: String,
        shortcuts: [ShortcutType]
    ) {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.setAccessibilityIdentifier("shortcut-section-\(identifier)")
        heading.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-section-\(identifier)"
        )

        let headingRowIndex = shortcutGrid.numberOfRows
        shortcutGrid.addRow(with: [
            heading,
            makePlaceholder(),
            makePlaceholder(),
            makePlaceholder(),
            makePlaceholder()
        ])
        shortcutGrid.mergeCells(
            inHorizontalRange: NSRange(
                location: 0,
                length: GridColumn.allCases.count
            ),
            verticalRange: NSRange(location: headingRowIndex, length: 1)
        )
        let headingRow = shortcutGrid.row(at: headingRowIndex)
        headingRow.height = 18
        headingRow.topPadding = headingRowIndex == 0 ? 0 : 12
        headingRow.bottomPadding = 4

        shortcuts.forEach(addShortcutRow)
    }

    private func addShortcutRow(_ shortcutType: ShortcutType) {
        let cells: [NSView]
        switch shortcutType {
        case .static(let identifier, let keys, let description):
            cells = makeStaticCells(
                identifier: identifier,
                keys: keys,
                description: description
            )
        case .configurable(let action):
            cells = makeConfigurableCells(action: action)
        }
        let row = shortcutGrid.addRow(with: cells)
        row.height = 28
        row.cell(at: GridColumn.shortcut.rawValue).xPlacement = .fill
        row.cell(at: GridColumn.action.rawValue).xPlacement = .fill
        row.cell(at: GridColumn.multiplier.rawValue).xPlacement = .fill
        row.cell(at: GridColumn.clear.rawValue).xPlacement = .fill
    }

    private func makePlaceholder() -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        return view
    }

    private func makeStaticCells(
        identifier: String,
        keys: String,
        description: String
    ) -> [NSView] {
        let emptyEnabled = makePlaceholder()

        let keysLabel = NSTextField(labelWithString: keys)
        keysLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        keysLabel.alignment = .center
        keysLabel.lineBreakMode = .byTruncatingTail
        keysLabel.wantsLayer = true
        keysLabel.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        keysLabel.layer?.cornerRadius = 4
        keysLabel.toolTip = keys
        keysLabel.setAccessibilityIdentifier("shortcut-key-static-\(identifier)")
        keysLabel.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-key-static-\(identifier)"
        )
        keysLabel.translatesAutoresizingMaskIntoConstraints = false

        // Inline NSButtons use a two-point horizontal alignment inset. Match
        // it for fixed pointer gestures so every key field shares one visible
        // leading and trailing edge.
        let keysCell = NSView()
        keysCell.setAccessibilityElement(false)
        keysCell.addSubview(keysLabel)
        NSLayoutConstraint.activate([
            keysLabel.leadingAnchor.constraint(
                equalTo: keysCell.leadingAnchor,
                constant: 2
            ),
            keysLabel.trailingAnchor.constraint(
                equalTo: keysCell.trailingAnchor,
                constant: -2
            ),
            keysLabel.centerYAnchor.constraint(equalTo: keysCell.centerYAnchor),
            keysLabel.heightAnchor.constraint(equalToConstant: 22)
        ])

        let descriptionLabel = NSTextField(labelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.toolTip = description
        descriptionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        descriptionLabel.setAccessibilityIdentifier(
            "shortcut-action-static-\(identifier)"
        )
        descriptionLabel.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-action-static-\(identifier)"
        )

        return [
            emptyEnabled,
            keysCell,
            descriptionLabel,
            makePlaceholder(),
            makePlaceholder()
        ]
    }

    private func makeConfigurableCells(
        action: ShortcutSettings.Action
    ) -> [NSView] {
        let enableButton = NSButton(
            checkboxWithTitle: "",
            target: self,
            action: #selector(enabledChanged(_:))
        )
        enableButton.toolTip = "Enable \(action.displayName)"
        enableButton.setAccessibilityLabel("Enable \(action.displayName)")
        enableButton.setAccessibilityIdentifier("shortcut-enable-\(action.rawValue)")
        enableButton.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-enable-\(action.rawValue)"
        )
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
        shortcutButton.setAccessibilityIdentifier("shortcut-key-\(action.rawValue)")
        shortcutButton.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-key-\(action.rawValue)"
        )
        shortcutButtons[action] = shortcutButton

        let description = action.displayName + (action.isGlobal ? " · Global" : "")
        let descriptionLabel = NSTextField(labelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.toolTip = description
        descriptionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.setAccessibilityIdentifier("shortcut-action-\(action.rawValue)")
        descriptionLabel.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-action-\(action.rawValue)"
        )

        let multiplierCell: NSView
        var rowFocusOrder: [NSView] = [enableButton, shortcutButton]
        if action.hasMultiplierVariant {
            let popup = makeMultiplierDropdown(action: action)
            multiplierCell = popup
            rowFocusOrder.append(popup)
        } else {
            multiplierCell = makePlaceholder()
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
        clearButton.setAccessibilityIdentifier("shortcut-clear-\(action.rawValue)")
        clearButton.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-clear-\(action.rawValue)"
        )
        clearButtons[action] = clearButton
        rowFocusOrder.append(clearButton)
        focusOrder.append(contentsOf: rowFocusOrder)

        return [
            enableButton,
            shortcutButton,
            descriptionLabel,
            multiplierCell,
            clearButton
        ]
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
        popup.setAccessibilityIdentifier("shortcut-multiplier-\(action.rawValue)")
        popup.identifier = NSUserInterfaceItemIdentifier(
            "shortcut-multiplier-\(action.rawValue)"
        )
        multiplierButtons[action] = popup
        return popup
    }

    private func configureFocusLoop() {
        guard focusOrder.count > 1 else { return }
        for (current, next) in zip(focusOrder, focusOrder.dropFirst()) {
            current.nextKeyView = next
        }
        focusOrder.last?.nextKeyView = focusOrder.first
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
        var errorAnnouncement: String?
        if let message = shortcutSettings.validationMessage {
            statusLabel.stringValue = message
            statusLabel.textColor = .systemRed
            statusLabel.superview?.layer?.backgroundColor =
                NSColor.systemRed.withAlphaComponent(0.13).cgColor
            statusLabel.setAccessibilityLabel("Shortcut error: \(message)")
            errorAnnouncement = "Shortcut error: \(message)"
        } else if let action = shortcutSettings.recordingAction {
            statusLabel.stringValue =
                "Press the new shortcut for \(action.displayName). Escape cancels; Delete clears it."
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.superview?.layer?.backgroundColor =
                NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            statusLabel.setAccessibilityLabel(statusLabel.stringValue)
        } else if case .partial(let registered, let failures) =
                    shortcutSettings.globalRegistrationStatus,
                  let firstFailure = failures.first {
            let remainingCount = failures.count - 1
            let suffix = remainingCount > 0
                ? " \(remainingCount) additional shortcut\(remainingCount == 1 ? "" : "s") failed."
                : ""
            statusLabel.stringValue =
                "\(firstFailure.recoveryDescription) \(registered) global shortcut\(registered == 1 ? "" : "s") remain active.\(suffix) Change the chord or close the conflicting app, then retry."
            statusLabel.textColor = .systemRed
            statusLabel.superview?.layer?.backgroundColor =
                NSColor.systemRed.withAlphaComponent(0.13).cgColor
            statusLabel.setAccessibilityLabel(
                "Global shortcut registration error: \(statusLabel.stringValue)"
            )
            errorAnnouncement =
                "Global shortcut registration error: \(statusLabel.stringValue)"
        } else {
            switch shortcutSettings.globalRegistrationStatus {
            case .disabled:
                statusLabel.stringValue =
                    "Global shortcuts are off. Local shortcuts remain available while Reframer is active."
            case .active(let count):
                statusLabel.stringValue =
                    "\(count) global shortcut\(count == 1 ? "" : "s") registered. Frame-step chords register only while a navigable video is loaded and locked. Reframer observes only those exact chords; no Accessibility or Input Monitoring permission is required."
            case .pending:
                statusLabel.stringValue = "Registering enabled global shortcuts…"
            case .partial:
                statusLabel.stringValue = "One or more global shortcuts could not be registered."
            }
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.superview?.layer?.backgroundColor =
                NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            statusLabel.setAccessibilityLabel(statusLabel.stringValue)
        }
        if let announcement = errorAnnouncementTracker
            .newMessageToAnnounce(errorAnnouncement) {
            postAccessibilityErrorAnnouncement(announcement, from: statusLabel)
        }
    }

    private func updateGlobalControls() {
        globalShortcutsButton.state = shortcutSettings.globalShortcutsEnabled ? .on : .off
        retryRegistrationButton.isEnabled =
            shortcutSettings.globalShortcutsEnabled
            && shortcutSettings.globalRegistrationStatus.hasFailures
        retryRegistrationButton.setAccessibilityValue(
            retryRegistrationButton.isEnabled
                ? "Registration failed; retry available"
                : "No retry needed"
        )
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

    @objc private func retryGlobalShortcutRegistration(_ sender: NSButton) {
        NotificationCenter.default.post(
            name: .reconfigureGlobalHotKeys,
            object: nil
        )
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

    override func layout() {
        let fixedColumnWidth =
            Self.enabledColumnWidth
            + Self.shortcutColumnWidth
            + Self.multiplierColumnWidth
            + Self.clearColumnWidth
        let spacingWidth =
            Self.gridColumnSpacing * CGFloat(GridColumn.allCases.count - 1)
        let gridWidth = max(
            0,
            scrollView.contentView.bounds.width
                - (Self.contentHorizontalInset * 2)
        )
        let actionWidth = max(
            Self.minimumActionColumnWidth,
            gridWidth - fixedColumnWidth - spacingWidth
        )
        if shortcutGrid.numberOfColumns == GridColumn.allCases.count,
           abs(
               shortcutGrid.column(at: GridColumn.action.rawValue).width
                   - actionWidth
           ) > 0.5 {
            shortcutGrid.column(at: GridColumn.action.rawValue).width = actionWidth
        }
        super.layout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            shortcutSettings.cancelRecording()
        }
    }

    deinit {
        if let displayOptionsObserver {
            NotificationCenter.default.removeObserver(displayOptionsObserver)
        }
        shortcutSettings.cancelRecording()
    }
}
