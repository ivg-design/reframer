import Cocoa
import Combine

/// Custom button that shows quick filter icon and opens dropdown for single-filter selection
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
        setAccessibilityElement(true)

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

        // Only update icon based on quickFilter (not advancedFilters)
        state.$quickFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let state = videoState else {
            imageView.image = NSImage(systemSymbolName: "checkerboard.rectangle", accessibilityDescription: "Opacity")
            imageView.contentTintColor = .secondaryLabelColor
            return
        }

        if let filter = state.quickFilter {
            // Quick filter active - show that filter's icon
            imageView.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: filter.rawValue)
            imageView.contentTintColor = .controlAccentColor
            toolTip = filter.rawValue
        } else {
            // No quick filter - show opacity icon (checkerboard)
            imageView.image = NSImage(systemSymbolName: "checkerboard.rectangle", accessibilityDescription: "Opacity")
            imageView.contentTintColor = .secondaryLabelColor
            toolTip = "Opacity"
        }
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        didShowMenu = false

        // Cmd+click: reset to default
        if event.modifierFlags.contains(.command) {
            resetFilterToDefault()
            return
        }

        // Start hold timer for menu
        holdTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
            self?.showFilterMenu(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil

        // Single click (no modifiers): cycle to next filter
        if !didShowMenu && !event.modifierFlags.contains(.command) {
            cycleToNextFilter()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // If dragging while menu is shown, let menu handle it
    }

    // MARK: - Filter Cycling

    private func cycleToNextFilter() {
        guard let state = videoState else { return }

        let simpleFilters = VideoFilter.simpleFilters
        guard !simpleFilters.isEmpty else { return }

        if let currentFilter = state.quickFilter,
           let currentIndex = simpleFilters.firstIndex(of: currentFilter) {
            // Move to next filter, or back to nil (opacity mode)
            let nextIndex = currentIndex + 1
            if nextIndex < simpleFilters.count {
                state.setQuickFilter(simpleFilters[nextIndex])
            } else {
                state.setQuickFilter(nil)  // Back to opacity
            }
        } else {
            // No filter active, start with first filter
            state.setQuickFilter(simpleFilters[0])
        }
    }

    private func resetFilterToDefault() {
        guard let state = videoState else { return }

        if state.quickFilter != nil {
            // Reset filter value to middle (0.5 normalized = default)
            state.quickFilterValue = 0.5
        } else {
            // Reset opacity to 100%
            state.opacity = 1.0
        }
    }

    // MARK: - Filter Menu (Single Select, Simple Filters Only)

    private func showFilterMenu(with event: NSEvent) {
        didShowMenu = true
        holdTimer?.invalidate()
        holdTimer = nil

        let menu = NSMenu()

        // "None" option to clear quick filter
        let noneItem = NSMenuItem()
        noneItem.title = "None"
        noneItem.image = NSImage(systemSymbolName: "circle.slash", accessibilityDescription: "None")
        noneItem.target = self
        noneItem.action = #selector(clearQuickFilter(_:))
        noneItem.state = (videoState?.quickFilter == nil) ? .on : .off
        menu.addItem(noneItem)

        menu.addItem(.separator())

        // Only show simple filters (single slider)
        for filter in VideoFilter.simpleFilters {
            let item = NSMenuItem()
            item.title = filter.rawValue
            item.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: filter.rawValue)
            item.target = self
            item.action = #selector(filterSelected(_:))
            item.representedObject = filter

            // Radio-style: checkmark on active filter only
            if videoState?.quickFilter == filter {
                item.state = .on
            } else {
                item.state = .off
            }

            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Advanced Filters option
        let advancedItem = NSMenuItem()
        advancedItem.title = "Advanced Filters..."
        advancedItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Advanced")
        advancedItem.target = self
        advancedItem.action = #selector(showAdvancedFilters(_:))
        menu.addItem(advancedItem)

        // Show menu at button location
        let location = NSPoint(x: 0, y: bounds.height)
        menu.popUp(positioning: nil, at: location, in: self)
    }

    @objc func filterSelected(_ sender: NSMenuItem) {
        guard let filter = sender.representedObject as? VideoFilter else { return }
        videoState?.setQuickFilter(filter)
    }

    @objc func clearQuickFilter(_ sender: Any?) {
        videoState?.setQuickFilter(nil)
    }

    @objc func showAdvancedFilters(_ sender: Any?) {
        videoState?.showFilterPanel = true
    }

    // MARK: - Right Click

    override func rightMouseDown(with event: NSEvent) {
        showFilterMenu(with: event)
    }

    // MARK: - Accessibility

    override func accessibilityLabel() -> String? {
        if let filter = videoState?.quickFilter {
            return "Filter: \(filter.rawValue)"
        }
        return "No filter active"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .button
    }
}
