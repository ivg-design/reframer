import Cocoa
import Combine

/// Flipped view for top-aligned scroll content
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Floating panel view with filter toggles and parameter sliders
class FilterPanelView: NSView {

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()

    private let visualEffectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let contentView = FlippedView()  // Flipped document view for top-aligned scroll
    private let contentStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "Advanced Filters")
    private let closeButton = NSButton()
    private let resetButton = NSButton()
    private let clearButton = NSButton()
    private var appearanceObserver: NSObjectProtocol?

    // Filter toggles
    private var filterToggles: [VideoFilter: NSSwitch] = [:]

    // Sliders organized by filter
    private var sliders: [String: NSSlider] = [:]
    private var valueLabels: [String: NSTextField] = [:]
    private var sliderFocusOrder: [NSSlider] = []

    // Container for parameter sliders
    private var parametersContainer = NSStackView()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    var preferredInitialFirstResponder: NSView {
        VideoFilter.allCases.compactMap { filterToggles[$0] }.first ?? closeButton
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Advanced filters")

        // Glass background
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .followsWindowActiveState
        visualEffectView.setAccessibilityElement(false)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffectView)

        // Title bar
        let titleBar = NSStackView()
        titleBar.orientation = .horizontal
        titleBar.spacing = 8
        titleBar.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor

        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePanel)
        configure(
            button: closeButton,
            identifier: "filter-panel-close",
            label: "Close advanced filters",
            help: "Close this panel and return to the previous control"
        )

        resetButton.bezelStyle = .rounded
        resetButton.title = "Reset"
        resetButton.font = .systemFont(ofSize: 11)
        resetButton.target = self
        resetButton.action = #selector(resetSettings)
        configure(
            button: resetButton,
            identifier: "filter-panel-reset",
            label: "Reset filter parameters",
            help: "Restore every advanced filter parameter to its default value"
        )

        clearButton.bezelStyle = .rounded
        clearButton.title = "Clear All"
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.target = self
        clearButton.action = #selector(clearAllFilters)
        configure(
            button: clearButton,
            identifier: "filter-panel-clear",
            label: "Clear all advanced filters",
            help: "Turn off every advanced filter"
        )

        titleBar.addArrangedSubview(titleLabel)
        let titleSpacer = NSView()
        titleSpacer.setAccessibilityElement(false)
        titleBar.addArrangedSubview(titleSpacer)
        titleBar.addArrangedSubview(clearButton)
        titleBar.addArrangedSubview(resetButton)
        titleBar.addArrangedSubview(closeButton)

        addSubview(titleBar)

        // Scroll view setup
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.setAccessibilityLabel("Advanced filter controls")
        addSubview(scrollView)

        // Document view for scrolling
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        // Content stack - TOP aligned
        contentStack.orientation = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        // Layout constraints
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleBar.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            // Document view fills scroll view width, height is content-based
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            // Content stack pinned to TOP of document view
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        buildStaticContent()
        updateAppearance()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAppearance()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let self else { return }
            self.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
            self.visualEffectView.wantsLayer = true
            self.visualEffectView.layer?.backgroundColor =
                NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                ? NSColor.windowBackgroundColor.cgColor
                : NSColor.clear.cgColor
        }
    }

    private func configure(
        button: NSButton,
        identifier: String,
        label: String,
        help: String
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(help)
        button.toolTip = help
    }

    private func accessibilitySlug(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func configureKeyboardFocusOrder() {
        let toggles = VideoFilter.allCases.compactMap { filterToggles[$0] as NSView? }
        let controls: [NSView] = toggles
            + sliderFocusOrder.map { $0 as NSView }
            + [clearButton, resetButton, closeButton]
        guard let first = controls.first else { return }
        for (current, next) in zip(controls, controls.dropFirst()) {
            current.nextKeyView = next
        }
        controls.last?.nextKeyView = first
    }

    // MARK: - Content Building

    private func buildStaticContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        filterToggles.removeAll()
        sliderFocusOrder.removeAll()

        // Build two-column grid of filter toggles with aligned columns
        let filters = VideoFilter.allCases
        let rowCount = (filters.count + 1) / 2

        // Create the grid container
        let gridContainer = NSStackView()
        gridContainer.orientation = .horizontal
        gridContainer.spacing = 20
        gridContainer.alignment = .top
        gridContainer.distribution = .fillEqually
        gridContainer.setAccessibilityElement(false)

        // Left column
        let leftColumn = NSStackView()
        leftColumn.orientation = .vertical
        leftColumn.spacing = 8
        leftColumn.alignment = .leading
        leftColumn.setAccessibilityElement(false)

        // Right column
        let rightColumn = NSStackView()
        rightColumn.orientation = .vertical
        rightColumn.spacing = 8
        rightColumn.alignment = .leading
        rightColumn.setAccessibilityElement(false)

        for i in 0..<filters.count {
            let filter = filters[i]
            let row = createFilterToggleRow(for: filter)
            filterToggles[filter] = row.toggle

            if i < rowCount {
                leftColumn.addArrangedSubview(row.container)
            } else {
                rightColumn.addArrangedSubview(row.container)
            }
        }

        gridContainer.addArrangedSubview(leftColumn)
        gridContainer.addArrangedSubview(rightColumn)

        contentStack.addArrangedSubview(gridContainer)

        // Parameters container
        parametersContainer = NSStackView()
        parametersContainer.orientation = .vertical
        parametersContainer.spacing = 8
        parametersContainer.alignment = .leading
        parametersContainer.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(parametersContainer)
        configureKeyboardFocusOrder()
    }

    private func createFilterToggleRow(for filter: VideoFilter) -> (container: NSView, toggle: NSSwitch) {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 6
        container.alignment = .centerY

        // Icon
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])

        // Label with fixed width for alignment
        let label = NSTextField(labelWithString: filter.rawValue)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 80).isActive = true

        // Toggle switch
        let toggle = NSSwitch()
        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(filterToggleChanged(_:))
        toggle.identifier = NSUserInterfaceItemIdentifier(
            "filter-toggle-\(accessibilitySlug(filter.rawValue))"
        )
        toggle.setAccessibilityElement(true)
        toggle.setAccessibilityLabel(filter.rawValue)
        toggle.setAccessibilityHelp(filter.description)
        toggle.toolTip = filter.description

        container.addArrangedSubview(icon)
        container.addArrangedSubview(label)
        container.addArrangedSubview(toggle)

        return (container, toggle)
    }

    /// Rebuild parameter sliders based on active filters
    private func rebuildParameters(for activeFilters: Set<VideoFilter>) {
        // Clear existing
        parametersContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sliders.removeAll()
        valueLabels.removeAll()
        sliderFocusOrder.removeAll()

        guard !activeFilters.isEmpty else {
            configureKeyboardFocusOrder()
            return
        }

        // Add separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.setAccessibilityElement(false)
        separator.translatesAutoresizingMaskIntoConstraints = false
        parametersContainer.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: 260).isActive = true

        // Add sliders for each active filter (in consistent order)
        let orderedFilters = VideoFilter.allCases.filter { activeFilters.contains($0) }

        for filter in orderedFilters {
            addParametersForFilter(filter)
        }

        // Update slider values from current settings
        if let settings = videoState?.filterSettings {
            updateSliders(from: settings)
        }
        configureKeyboardFocusOrder()
    }

    private func addParametersForFilter(_ filter: VideoFilter) {
        // Add filter name as header
        let header = NSTextField(labelWithString: filter.rawValue)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .controlAccentColor
        parametersContainer.addArrangedSubview(header)

        // Add sliders based on filter type
        switch filter {
        case .brightness:
            addSlider(key: "brightnessLevel", label: "Level", filter: filter, min: -1, max: 1, defaultValue: 0)

        case .contrast:
            addSlider(key: "contrastLevel", label: "Level", filter: filter, min: 0.25, max: 4, defaultValue: 1.0)

        case .saturation:
            addSlider(key: "saturationLevel", label: "Level", filter: filter, min: 0, max: 2, defaultValue: 1.0)

        case .exposure:
            addSlider(key: "exposure", label: "EV", filter: filter, min: -3, max: 3, defaultValue: 0)

        case .edges:
            addSlider(key: "edgeIntensity", label: "Intensity", filter: filter, min: 0, max: 10, defaultValue: 1.0)

        case .sharpen:
            addSlider(key: "sharpness", label: "Amount", filter: filter, min: 0, max: 2, defaultValue: 0.4)

        case .unsharpMask:
            addSlider(key: "unsharpRadius", label: "Radius", filter: filter, min: 0, max: 10, defaultValue: 2.5)
            addSlider(key: "unsharpIntensity", label: "Intensity", filter: filter, min: 0, max: 2, defaultValue: 0.5)

        case .monochrome:
            addSlider(key: "monochromeR", label: "Red", filter: filter, min: 0, max: 1, defaultValue: 0.6)
            addSlider(key: "monochromeG", label: "Green", filter: filter, min: 0, max: 1, defaultValue: 0.45)
            addSlider(key: "monochromeB", label: "Blue", filter: filter, min: 0, max: 1, defaultValue: 0.3)
            addSlider(key: "monochromeIntensity", label: "Intensity", filter: filter, min: 0, max: 1, defaultValue: 1.0)

        case .invert, .noir:
            let noParams = NSTextField(labelWithString: "No adjustable parameters")
            noParams.font = .systemFont(ofSize: 10)
            noParams.textColor = .tertiaryLabelColor
            noParams.setAccessibilityLabel("\(filter.rawValue) has no adjustable parameters")
            parametersContainer.addArrangedSubview(noParams)

        case .lineArt:
            addSlider(key: "lineArtEdge", label: "Sensitivity", filter: filter, min: 0.1, max: 200, defaultValue: 50)
            addSlider(key: "lineArtThreshold", label: "Threshold", filter: filter, min: 0, max: 1, defaultValue: 0.1)
            addSlider(key: "lineArtContrast", label: "Darkness", filter: filter, min: 1, max: 200, defaultValue: 50)
        }
    }

    private func addSlider(
        key: String,
        label: String,
        filter: VideoFilter,
        min: Double,
        max: Double,
        defaultValue: Double
    ) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .labelColor
        nameLabel.setAccessibilityElement(false)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let slider = NSSlider()
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = defaultValue
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.identifier = NSUserInterfaceItemIdentifier(
            "filter-slider-\(accessibilitySlug(key))"
        )
        slider.controlSize = .small
        slider.setAccessibilityIdentifier("filter-slider-\(accessibilitySlug(key))")
        slider.setAccessibilityLabel("\(filter.rawValue) \(label.lowercased())")
        slider.setAccessibilityHelp(
            "Adjust \(label.lowercased()) for the \(filter.rawValue.lowercased()) filter"
        )
        slider.toolTip = slider.accessibilityHelp()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        sliders[key] = slider
        sliderFocusOrder.append(slider)

        let valueLabel = NSTextField(labelWithString: String(format: "%.2f", defaultValue))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setAccessibilityElement(false)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        valueLabels[key] = valueLabel

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)

        parametersContainer.addArrangedSubview(row)
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        state.$advancedFilters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] advancedFilters in
                self?.updateFilterToggles(activeFilters: advancedFilters)
                self?.rebuildParameters(for: advancedFilters)
            }
            .store(in: &cancellables)

        state.$filterSettings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.updateSliders(from: settings)
            }
            .store(in: &cancellables)
    }

    private func updateFilterToggles(activeFilters: Set<VideoFilter>) {
        for (filter, toggle) in filterToggles {
            toggle.state = activeFilters.contains(filter) ? .on : .off
        }
    }

    private func updateSliders(from settings: FilterSettings) {
        setSlider("brightnessLevel", value: settings.brightnessLevel)
        setSlider("contrastLevel", value: settings.contrastLevel)
        setSlider("saturationLevel", value: settings.saturationLevel)
        setSlider("exposure", value: settings.exposure)
        setSlider("edgeIntensity", value: settings.edgeIntensity)
        setSlider("sharpness", value: settings.sharpness)
        setSlider("unsharpRadius", value: settings.unsharpRadius)
        setSlider("unsharpIntensity", value: settings.unsharpIntensity)
        setSlider("monochromeR", value: settings.monochromeR)
        setSlider("monochromeG", value: settings.monochromeG)
        setSlider("monochromeB", value: settings.monochromeB)
        setSlider("monochromeIntensity", value: settings.monochromeIntensity)
        setSlider("lineArtEdge", value: settings.lineArtEdge)
        setSlider("lineArtThreshold", value: settings.lineArtThreshold)
        setSlider("lineArtContrast", value: settings.lineArtContrast)
    }

    private func setSlider(_ key: String, value: Double) {
        sliders[key]?.doubleValue = value
        valueLabels[key]?.stringValue = String(format: "%.2f", value)
    }

    // MARK: - Actions

    @objc private func filterToggleChanged(_ sender: NSSwitch) {
        guard let filter = filterToggles.first(where: { $0.value === sender })?.key else {
            return
        }
        videoState?.toggleAdvancedFilter(filter)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let key = sliders.first(where: { $0.value === sender })?.key,
              var settings = videoState?.filterSettings else { return }

        let value = sender.doubleValue
        valueLabels[key]?.stringValue = String(format: "%.2f", value)

        switch key {
        case "brightnessLevel": settings.brightnessLevel = value
        case "contrastLevel": settings.contrastLevel = value
        case "saturationLevel": settings.saturationLevel = value
        case "exposure": settings.exposure = value
        case "edgeIntensity": settings.edgeIntensity = value
        case "sharpness": settings.sharpness = value
        case "unsharpRadius": settings.unsharpRadius = value
        case "unsharpIntensity": settings.unsharpIntensity = value
        case "monochromeR": settings.monochromeR = value
        case "monochromeG": settings.monochromeG = value
        case "monochromeB": settings.monochromeB = value
        case "monochromeIntensity": settings.monochromeIntensity = value
        case "lineArtEdge": settings.lineArtEdge = value
        case "lineArtThreshold": settings.lineArtThreshold = value
        case "lineArtContrast": settings.lineArtContrast = value
        default: break
        }

        videoState?.filterSettings = settings
    }

    @objc private func closePanel() {
        videoState?.showFilterPanel = false
    }

    @objc private func resetSettings() {
        videoState?.filterSettings = .defaults
    }

    @objc private func clearAllFilters() {
        videoState?.clearAdvancedFilters()
    }
}
