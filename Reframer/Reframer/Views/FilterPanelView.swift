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
    private let titleLabel = NSTextField(labelWithString: "Filter Settings")
    private let closeButton = NSButton()
    private let resetButton = NSButton()
    private let clearButton = NSButton()

    // Filter checkboxes
    private var filterCheckboxes: [VideoFilter: NSButton] = [:]

    // Sliders organized by section
    private var sliders: [String: NSSlider] = [:]
    private var valueLabels: [String: NSTextField] = [:]

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
        contentStack.spacing = 12
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

        buildContent()
    }

    // MARK: - Content Building

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        filterCheckboxes.removeAll()
        sliders.removeAll()
        valueLabels.removeAll()

        // Active Filters section
        addSection("Active Filters")
        buildFilterCheckboxes()

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        // Parameter Sliders
        addSection("Filter Parameters")

        // Edge Detection
        addSlider(key: "edgeIntensity", label: "Edge Intensity", min: 0, max: 10, defaultValue: 1.0)

        // Sharpen
        addSlider(key: "sharpness", label: "Sharpness", min: 0, max: 2, defaultValue: 0.4)

        // Unsharp Mask
        addSlider(key: "unsharpRadius", label: "Unsharp Radius", min: 0, max: 10, defaultValue: 2.5)
        addSlider(key: "unsharpIntensity", label: "Unsharp Intensity", min: 0, max: 2, defaultValue: 0.5)

        // Color Controls
        addSlider(key: "brightness", label: "Brightness", min: -1, max: 1, defaultValue: 0)
        addSlider(key: "contrast", label: "Contrast", min: 0.25, max: 4, defaultValue: 1.5)
        addSlider(key: "saturation", label: "Saturation", min: 0, max: 2, defaultValue: 1.0)

        // Monochrome
        addSlider(key: "monochromeR", label: "Mono Red", min: 0, max: 1, defaultValue: 0.6)
        addSlider(key: "monochromeG", label: "Mono Green", min: 0, max: 1, defaultValue: 0.45)
        addSlider(key: "monochromeB", label: "Mono Blue", min: 0, max: 1, defaultValue: 0.3)
        addSlider(key: "monochromeIntensity", label: "Mono Intensity", min: 0, max: 1, defaultValue: 1.0)

        // Line Overlay
        addSlider(key: "lineOverlayNoise", label: "Line Noise", min: 0, max: 0.1, defaultValue: 0.07)
        addSlider(key: "lineOverlaySharpness", label: "Line Sharpness", min: 0, max: 2, defaultValue: 0.71)
        addSlider(key: "lineOverlayEdge", label: "Line Edge", min: 0, max: 200, defaultValue: 1.0)
        addSlider(key: "lineOverlayThreshold", label: "Line Threshold", min: 0, max: 1, defaultValue: 0.1)
        addSlider(key: "lineOverlayContrast", label: "Line Contrast", min: 0.25, max: 200, defaultValue: 50)

        // Exposure
        addSlider(key: "exposure", label: "Exposure EV", min: 0, max: 3, defaultValue: 1.0)
    }

    private func buildFilterCheckboxes() {
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 4
        grid.columnSpacing = 8

        // Create 2 columns of checkboxes
        let filters = VideoFilter.allCases
        let midpoint = (filters.count + 1) / 2

        for i in 0..<midpoint {
            let leftFilter = filters[i]
            let leftCheckbox = createFilterCheckbox(for: leftFilter)
            filterCheckboxes[leftFilter] = leftCheckbox

            if i + midpoint < filters.count {
                let rightFilter = filters[i + midpoint]
                let rightCheckbox = createFilterCheckbox(for: rightFilter)
                filterCheckboxes[rightFilter] = rightCheckbox
                grid.addRow(with: [leftCheckbox, rightCheckbox])
            } else {
                grid.addRow(with: [leftCheckbox, NSView()])
            }
        }

        contentStack.addArrangedSubview(grid)
    }

    private func createFilterCheckbox(for filter: VideoFilter) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: filter.rawValue, target: self, action: #selector(filterCheckboxChanged(_:)))
        checkbox.font = .systemFont(ofSize: 11)
        checkbox.identifier = NSUserInterfaceItemIdentifier(filter.rawValue)
        return checkbox
    }

    private func addSection(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        contentStack.addArrangedSubview(label)
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
            nameLabel.widthAnchor.constraint(equalToConstant: 100),
            valueLabel.widthAnchor.constraint(equalToConstant: 50)
        ])

        contentStack.addArrangedSubview(row)
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        state.$activeFilters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeFilters in
                self?.updateFilterCheckboxes(activeFilters: activeFilters)
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
        setSlider("saturation", value: settings.saturation)
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
        case "saturation": settings.saturation = value
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
