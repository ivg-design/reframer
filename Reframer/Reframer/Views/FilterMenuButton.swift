import Cocoa
import Combine

/// Native pop-up button for single-filter selection. Using NSPopUpButton keeps
/// the menu in AppKit's keyboard and accessibility hierarchy instead of
/// presenting a transient menu from an NSView that merely advertises a
/// pop-up-button role.
class FilterMenuButton: NSPopUpButton, ReframerShortcutOwningResponder {

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect, pullsDown: false)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel("Quick filter")
        setAccessibilityHelp("Choose a quick video filter or open advanced filters")
        setAccessibilityIdentifier("quick-filter-menu")
        setAccessibilityEnabled(true)
        isBordered = false
        bezelStyle = .inline
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .exterior

        updateIcon()
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }
        updateIcon()

        // Only update icon based on quickFilter (not advancedFilters)
        state.$quickFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        let state = videoState
        menu = makeFilterMenu()

        if let filter = state?.quickFilter {
            // Quick filter active - show that filter's icon
            selectItem(withTitle: filter.rawValue)
            image = NSImage(
                systemSymbolName: filter.iconName,
                accessibilityDescription: filter.rawValue
            )
            contentTintColor = .controlAccentColor
            toolTip = "Quick filter: \(filter.rawValue)"
            setAccessibilityValue(filter.rawValue)
        } else {
            // No quick filter - show opacity icon (checkerboard)
            selectItem(withTitle: "None")
            image = NSImage(
                systemSymbolName: "checkerboard.rectangle",
                accessibilityDescription: "Opacity"
            )
            contentTintColor = .secondaryLabelColor
            toolTip = "Quick filter: None"
            setAccessibilityValue("None")
        }
    }

    private func resetFilterToDefault() {
        guard let state = videoState else { return }

        if let filter = state.quickFilter {
            state.quickFilterValue = filter.defaultNormalizedValue
        } else {
            // Reset opacity to 100%
            state.opacity = 1.0
        }
        updateIcon()
    }

    // MARK: - Filter Menu (Single Select, Simple Filters Only)

    private func quickFilterIdentifier(for filter: VideoFilter) -> NSUserInterfaceItemIdentifier {
        let slug = filter.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        return NSUserInterfaceItemIdentifier("quick-filter-\(slug)")
    }

    func makeFilterMenu() -> NSMenu {
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
            item.identifier = quickFilterIdentifier(for: filter)
            item.setAccessibilityLabel("Quick filter: \(filter.rawValue)")

            // Radio-style: checkmark on active filter only
            if videoState?.quickFilter == filter {
                item.state = .on
            } else {
                item.state = .off
            }

            menu.addItem(item)
        }

        let resetItem = NSMenuItem(
            title: videoState?.quickFilter == nil ? "Reset Opacity" : "Reset Filter Strength",
            action: #selector(resetCurrentValue(_:)),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        // Advanced Filters option
        let advancedItem = NSMenuItem()
        advancedItem.title = "Advanced Filters..."
        advancedItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Advanced")
        advancedItem.target = self
        advancedItem.action = #selector(showAdvancedFilters(_:))
        menu.addItem(advancedItem)

        return menu
    }

    @objc private func resetCurrentValue(_ sender: Any?) {
        resetFilterToDefault()
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
        updateIcon()
    }

    func ownsReframerShortcut(_ stroke: ShortcutKeystroke) -> Bool {
        stroke.modifiers == 0 && [36, 49, 76].contains(stroke.keyCode)
    }
}
