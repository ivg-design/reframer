import Cocoa
import Combine

/// Floating panel view with filter toggles and parameter sliders
class FilterPanelView: NSView {

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()

    private let visualEffectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "Filters")
    private let closeButton = NSButton()
    private let resetButton = NSButton()
    private let clearButton = NSButton()

    // Filter toggles
    private var filterToggles: [VideoFilter: NSSwitch] = [:]

    // Sliders organized by filter
    private var sliders: [String: NSSlider] = [:]
    private var valueLabels: [String: NSTextField] = [:]

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

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        // Glass background
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
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
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePanel)

        resetButton.bezelStyle = .rounded
        resetButton.title = "Reset"
        resetButton.font = .systemFont(ofSize: 11)
        resetButton.target = self
        resetButton.action = #selector(resetSettings)

        clearButton.bezelStyle = .rounded
        clearButton.title = "Clear All"
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.target = self
        clearButton.action = #selector(clearAllFilters)

        titleBar.addArrangedSubview(titleLabel)
        titleBar.addArrangedSubview(NSView()) // Spacer
        titleBar.addArrangedSubview(clearButton)
        titleBar.addArrangedSubview(resetButton)
        titleBar.addArrangedSubview(closeButton)

        addSubview(titleBar)

        // Scroll view for content
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        addSubview(scrollView)

        // Content stack
        contentStack.orientation = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.documentView = contentStack
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        // Layout
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

            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: scrollView.documentView!.topAnchor)
        ])

        buildStaticContent()
    }

    // MARK: - Content Building

    private func buildStaticContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        filterToggles.removeAll()

        // Build two-column grid of filter toggles
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = 16
        grid.rowAlignment = .firstBaseline

        let filters = VideoFilter.allCases
        let rowCount = (filters.count + 1) / 2

        for row in 0..<rowCount {
            let leftIndex = row
            let rightIndex = row + rowCount

            let leftView = createFilterToggleRow(for: filters[leftIndex])
            filterToggles[filters[leftIndex]] = leftView.toggle

            if rightIndex < filters.count {
                let rightView = createFilterToggleRow(for: filters[rightIndex])
                filterToggles[filters[rightIndex]] = rightView.toggle
                grid.addRow(with: [leftView.container, rightView.container])
            } else {
                grid.addRow(with: [leftView.container, NSView()])
            }
        }

        // Set column widths
        if grid.numberOfColumns >= 2 {
            grid.column(at: 0).width = 130
            grid.column(at: 1).width = 130
        }

        contentStack.addArrangedSubview(grid)

        // Parameters container
        parametersContainer = NSStackView()
        parametersContainer.orientation = .vertical
        parametersContainer.spacing = 8
        parametersContainer.alignment = .leading
        parametersContainer.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(parametersContainer)

        // Width constraint for parameters
        parametersContainer.widthAnchor.constraint(equalToConstant: 280).isActive = true
    }

    private func createFilterToggleRow(for filter: VideoFilter) -> (container: NSView, toggle: NSSwitch) {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 6
        container.alignment = .centerY

        // Icon
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: filter.rawValue)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        // Label
        let label = NSTextField(labelWithString: filter.rawValue)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        // Toggle switch
        let toggle = NSSwitch()
        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(filterToggleChanged(_:))
        toggle.identifier = NSUserInterfaceItemIdentifier(filter.rawValue)

        container.addArrangedSubview(icon)
        container.addArrangedSubview(label)
        container.addArrangedSubview(toggle)

        // Make label expand to fill space
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        return (container, toggle)
    }

    /// Rebuild parameter sliders based on active filters
    private func rebuildParameters(for activeFilters: Set<VideoFilter>) {
        // Clear existing
        parametersContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sliders.removeAll()
        valueLabels.removeAll()

        guard !activeFilters.isEmpty else { return }

        // Add separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        parametersContainer.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: parametersContainer.widthAnchor).isActive = true

        // Add sliders for each active filter (in consistent order)
        let orderedFilters = VideoFilter.allCases.filter { activeFilters.contains($0) }

        for filter in orderedFilters {
            addParametersForFilter(filter)
        }

        // Update slider values from current settings
        if let settings = videoState?.filterSettings {
            updateSliders(from: settings)
        }
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
            addSlider(key: "brightnessLevel", label: "Level", min: -1, max: 1, defaultValue: 0)

        case .contrast:
            addSlider(key: "contrastLevel", label: "Level", min: 0.25, max: 4, defaultValue: 1.0)

        case .saturation:
            addSlider(key: "saturationLevel", label: "Level", min: 0, max: 2, defaultValue: 1.0)

        case .exposure:
            addSlider(key: "exposure", label: "EV", min: -3, max: 3, defaultValue: 0)

        case .edges:
            addSlider(key: "edgeIntensity", label: "Intensity", min: 0, max: 10, defaultValue: 1.0)

        case .sharpen:
            addSlider(key: "sharpness", label: "Amount", min: 0, max: 2, defaultValue: 0.4)

        case .unsharpMask:
            addSlider(key: "unsharpRadius", label: "Radius", min: 0, max: 10, defaultValue: 2.5)
            addSlider(key: "unsharpIntensity", label: "Intensity", min: 0, max: 2, defaultValue: 0.5)

        case .monochrome:
            addSlider(key: "monochromeR", label: "Red", min: 0, max: 1, defaultValue: 0.6)
            addSlider(key: "monochromeG", label: "Green", min: 0, max: 1, defaultValue: 0.45)
            addSlider(key: "monochromeB", label: "Blue", min: 0, max: 1, defaultValue: 0.3)
            addSlider(key: "monochromeIntensity", label: "Intensity", min: 0, max: 1, defaultValue: 1.0)

        case .invert, .noir:
            // No parameters
            let noParams = NSTextField(labelWithString: "No adjustable parameters")
            noParams.font = .systemFont(ofSize: 10)
            noParams.textColor = .tertiaryLabelColor
            parametersContainer.addArrangedSubview(noParams)

        case .lineOverlay:
            addSlider(key: "lineOverlayNoise", label: "Noise", min: 0, max: 0.1, defaultValue: 0.07)
            addSlider(key: "lineOverlaySharpness", label: "Sharpness", min: 0, max: 2, defaultValue: 0.71)
            addSlider(key: "lineOverlayEdge", label: "Edge", min: 0, max: 200, defaultValue: 1.0)
            addSlider(key: "lineOverlayThreshold", label: "Threshold", min: 0, max: 1, defaultValue: 0.1)
            addSlider(key: "lineOverlayContrast", label: "Contrast", min: 0.25, max: 200, defaultValue: 50)
        }
    }

    private func addSlider(key: String, label: String, min: Double, max: Double, defaultValue: Double) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let slider = NSSlider()
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = defaultValue
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false
        sliders[key] = slider

        let valueLabel = NSTextField(labelWithString: String(format: "%.2f", defaultValue))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabels[key] = valueLabel

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)

        // Set explicit widths
        NSLayoutConstraint.activate([
            nameLabel.widthAnchor.constraint(equalToConstant: 65),
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            valueLabel.widthAnchor.constraint(equalToConstant: 45),
            row.widthAnchor.constraint(equalToConstant: 280)
        ])

        parametersContainer.addArrangedSubview(row)
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        state.$activeFilters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeFilters in
                self?.updateFilterToggles(activeFilters: activeFilters)
                self?.rebuildParameters(for: activeFilters)
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
        setSlider("lineOverlayNoise", value: settings.lineOverlayNoise)
        setSlider("lineOverlaySharpness", value: settings.lineOverlaySharpness)
        setSlider("lineOverlayEdge", value: settings.lineOverlayEdge)
        setSlider("lineOverlayThreshold", value: settings.lineOverlayThreshold)
        setSlider("lineOverlayContrast", value: settings.lineOverlayContrast)
    }

    private func setSlider(_ key: String, value: Double) {
        sliders[key]?.doubleValue = value
        valueLabels[key]?.stringValue = String(format: "%.2f", value)
    }

    // MARK: - Actions

    @objc private func filterToggleChanged(_ sender: NSSwitch) {
        guard let identifier = sender.identifier?.rawValue,
              let filter = VideoFilter.allCases.first(where: { $0.rawValue == identifier }) else { return }
        videoState?.toggleFilter(filter)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let key = sender.identifier?.rawValue,
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
        case "lineOverlayNoise": settings.lineOverlayNoise = value
        case "lineOverlaySharpness": settings.lineOverlaySharpness = value
        case "lineOverlayEdge": settings.lineOverlayEdge = value
        case "lineOverlayThreshold": settings.lineOverlayThreshold = value
        case "lineOverlayContrast": settings.lineOverlayContrast = value
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
        videoState?.clearAllFilters()
    }
}
