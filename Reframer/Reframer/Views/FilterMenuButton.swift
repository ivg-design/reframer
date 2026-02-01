import Cocoa
import Combine

/// Custom button that toggles filter panel on click and shows toggle menu on hold
class FilterMenuButton: NSView {

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()
    private let imageView = NSImageView()
    private var holdTimer: Timer?
    private var didShowMenu = false

    private let holdDuration: TimeInterval = 0.3  // 300ms hold to show menu

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

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20)
        ])

        updateIcon()
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        state.$activeFilters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        // Always show checkerboard/opacity icon
        let image = NSImage(systemSymbolName: "rectangle.pattern.checkered", accessibilityDescription: "Filters")
        imageView.image = image

        // Tint when any filters are active
        let hasActiveFilters = !(videoState?.activeFilters.isEmpty ?? true)
        if hasActiveFilters {
            imageView.contentTintColor = .controlAccentColor
        } else {
            imageView.contentTintColor = .secondaryLabelColor
        }

        // Build tooltip showing active filters
        if let state = videoState, !state.activeFilters.isEmpty {
            let filterNames = state.orderedActiveFilters.map { $0.rawValue }.joined(separator: ", ")
            toolTip = "Filters: \(filterNames)"
        } else {
            toolTip = "No filters active"
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        didShowMenu = false

        // Start hold timer
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.showFilterMenu(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil

        // If we didn't show menu, toggle filter panel
        if !didShowMenu {
            videoState?.showFilterPanel.toggle()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // If dragging while menu is shown, let menu handle it
    }

    // MARK: - Filter Menu

    private func showFilterMenu(with event: NSEvent) {
        didShowMenu = true
        holdTimer?.invalidate()
        holdTimer = nil

        let menu = NSMenu()

        // Add all filters as toggleable items
        for filter in VideoFilter.allCases {
            let item = NSMenuItem()
            item.title = filter.rawValue
            item.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: filter.rawValue)
            item.target = self
            item.action = #selector(filterToggled(_:))
            item.representedObject = filter

            // Show checkmark if filter is active
            if videoState?.isFilterActive(filter) == true {
                item.state = .on
            } else {
                item.state = .off
            }

            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Add "Clear All Filters" option
        let clearItem = NSMenuItem()
        clearItem.title = "Clear All Filters"
        clearItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Clear")
        clearItem.target = self
        clearItem.action = #selector(clearAllFilters)
        clearItem.isEnabled = !(videoState?.activeFilters.isEmpty ?? true)
        menu.addItem(clearItem)

        menu.addItem(.separator())

        // Add "Filter Settings..." option
        let settingsItem = NSMenuItem()
        settingsItem.title = "Filter Settings..."
        settingsItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Settings")
        settingsItem.target = self
        settingsItem.action = #selector(showFilterSettings)
        menu.addItem(settingsItem)

        // Show menu at button location
        let location = NSPoint(x: 0, y: bounds.height)
        menu.popUp(positioning: nil, at: location, in: self)
    }

    @objc private func filterToggled(_ sender: NSMenuItem) {
        guard let filter = sender.representedObject as? VideoFilter else { return }
        videoState?.toggleFilter(filter)
    }

    @objc private func clearAllFilters() {
        videoState?.clearAllFilters()
    }

    @objc private func showFilterSettings() {
        videoState?.showFilterPanel = true
    }

    // MARK: - Right Click

    override func rightMouseDown(with event: NSEvent) {
        showFilterMenu(with: event)
    }

    // MARK: - Accessibility

    override func accessibilityLabel() -> String? {
        if let state = videoState, !state.activeFilters.isEmpty {
            let count = state.activeFilters.count
            return "Filters: \(count) active"
        }
        return "Filters: None active"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .button
    }
}
