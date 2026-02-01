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

    // Filter checkboxes
    private var filterCheckboxes: [VideoFilter: NSButton] = [:]

    // Sliders organized by filter
    private var sliders: [String: NSSlider] = [:]
    private var valueLabels: [String: NSTextField] = [:]

    // Container for parameter sliders (rebuilt when filters change)
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

            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -20)
        ])

        buildStaticContent()
    }

    // MARK: - Content Building

    private func buildStaticContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        filterCheckboxes.removeAll()

        // Build all filter checkboxes in a vertical list
        let checkboxContainer = NSStackView()
        checkboxContainer.orientation = .vertical
        checkboxContainer.spacing = 6
        checkboxContainer.alignment = .leading

        for filter in VideoFilter.allCases {
            let checkbox = NSButton(checkboxWithTitle: filter.rawValue, target: self, action: #selector(filterCheckboxChanged(_:)))
            checkbox.font = .systemFont(ofSize: 12)
            checkbox.identifier = NSUserInterfaceItemIdentifier(filter.rawValue)
            filterCheckboxes[filter] = checkbox
            checkboxContainer.addArrangedSubview(checkbox)
        }

        contentStack.addArrangedSubview(checkboxContainer)

        // Parameters container (will be populated dynamically)
        parametersContainer.orientation = .vertical
        parametersContainer.spacing = 12
        parametersContainer.alignment = .leading
        parametersContainer.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(parametersContainer)
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
        case .edges:
            addSlider(key: "edgeIntensity", label: "Intensity", min: 0, max: 10, defaultValue: 1.0)

        case .sharpen:
            addSlider(key: "sharpness", label: "Sharpness", min: 0, max: 2, defaultValue: 0.4)

        case .unsharpMask:
            addSlider(key: "unsharpRadius", label: "Radius", min: 0, max: 10, defaultValue: 2.5)
            addSlider(key: "unsharpIntensity", label: "Intensity", min: 0, max: 2, defaultValue: 0.5)

        case .contrast:
            addSlider(key: "brightness", label: "Brightness", min: -1, max: 1, defaultValue: 0)
            addSlider(key: "contrast", label: "Contrast", min: 0.25, max: 4, defaultValue: 1.5)

        case .saturation:
            addSlider(key: "saturationLevel", label: "Level", min: 0, max: 2, defaultValue: 1.0)

        case .monochrome:
            addSlider(key: "monochromeR", label: "Red", min: 0, max: 1, defaultValue: 0.6)
            addSlider(key: "monochromeG", label: "Green", min: 0, max: 1, defaultValue: 0.45)
            addSlider(key: "monochromeB", label: "Blue", min: 0, max: 1, defaultValue: 0.3)
            addSlider(key: "monochromeIntensity", label: "Intensity", min: 0, max: 1, defaultValue: 1.0)

        case .invert:
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

        case .noir:
            // No parameters
            let noParams = NSTextField(labelWithString: "No adjustable parameters")
            noParams.font = .systemFont(ofSize: 10)
            noParams.textColor = .tertiaryLabelColor
            parametersContainer.addArrangedSubview(noParams)

        case .exposure:
            addSlider(key: "exposure", label: "EV", min: -3, max: 3, defaultValue: 0)
        }
    }

    private func addSlider(key: String, label: String, min: Double, max: Double, defaultValue: Double) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .labelColor
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let slider = NSSlider()
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = defaultValue
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.identifier = NSUserInterfaceItemIdentifier(key)
        slider.controlSize = .small
        sliders[key] = slider

        let valueLabel = NSTextField(labelWithString: String(format: "%.2f", defaultValue))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        valueLabels[key] = valueLabel

        row.addArrangedSubview(nameLabel)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)

        NSLayoutConstraint.activate([
            nameLabel.widthAnchor.constraint(equalToConstant: 70),
            valueLabel.widthAnchor.constraint(equalToConstant: 45)
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
                self?.updateFilterCheckboxes(activeFilters: activeFilters)
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

    private func updateFilterCheckboxes(activeFilters: Set<VideoFilter>) {
        for (filter, checkbox) in filterCheckboxes {
            checkbox.state = activeFilters.contains(filter) ? .on : .off
        }
    }

    private func updateSliders(from settings: FilterSettings) {
        setSlider("edgeIntensity", value: settings.edgeIntensity)
        setSlider("sharpness", value: settings.sharpness)
        setSlider("unsharpRadius", value: settings.unsharpRadius)
        setSlider("unsharpIntensity", value: settings.unsharpIntensity)
        setSlider("brightness", value: settings.brightness)
        setSlider("contrast", value: settings.contrast)
        setSlider("saturationLevel", value: settings.saturationLevel)
        setSlider("monochromeR", value: settings.monochromeR)
        setSlider("monochromeG", value: settings.monochromeG)
        setSlider("monochromeB", value: settings.monochromeB)
        setSlider("monochromeIntensity", value: settings.monochromeIntensity)
        setSlider("lineOverlayNoise", value: settings.lineOverlayNoise)
        setSlider("lineOverlaySharpness", value: settings.lineOverlaySharpness)
        setSlider("lineOverlayEdge", value: settings.lineOverlayEdge)
        setSlider("lineOverlayThreshold", value: settings.lineOverlayThreshold)
        setSlider("lineOverlayContrast", value: settings.lineOverlayContrast)
        setSlider("exposure", value: settings.exposure)
    }

    private func setSlider(_ key: String, value: Double) {
        sliders[key]?.doubleValue = value
        valueLabels[key]?.stringValue = String(format: "%.2f", value)
    }

    // MARK: - Actions

    @objc private func filterCheckboxChanged(_ sender: NSButton) {
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
        case "edgeIntensity": settings.edgeIntensity = value
        case "sharpness": settings.sharpness = value
        case "unsharpRadius": settings.unsharpRadius = value
        case "unsharpIntensity": settings.unsharpIntensity = value
        case "brightness": settings.brightness = value
        case "contrast": settings.contrast = value
        case "saturationLevel": settings.saturationLevel = value
        case "monochromeR": settings.monochromeR = value
        case "monochromeG": settings.monochromeG = value
        case "monochromeB": settings.monochromeB = value
        case "monochromeIntensity": settings.monochromeIntensity = value
        case "lineOverlayNoise": settings.lineOverlayNoise = value
        case "lineOverlaySharpness": settings.lineOverlaySharpness = value
        case "lineOverlayEdge": settings.lineOverlayEdge = value
        case "lineOverlayThreshold": settings.lineOverlayThreshold = value
        case "lineOverlayContrast": settings.lineOverlayContrast = value
        case "exposure": settings.exposure = value
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
