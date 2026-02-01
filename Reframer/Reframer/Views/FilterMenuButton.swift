import Cocoa
import Combine

/// Custom button that cycles through filters on click and shows menu on hold
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

        state.$activeFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        let filter = videoState?.activeFilter ?? .none
        let symbolName = filter.iconName
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: filter.rawValue)
        imageView.image = image

        // Tint active filters differently
        if filter == .none {
            imageView.contentTintColor = .secondaryLabelColor
        } else {
            imageView.contentTintColor = .controlAccentColor
        }

        toolTip = filter.rawValue
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

        // If we didn't show menu, cycle filter
        if !didShowMenu {
            videoState?.cycleFilter()
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

        // Add all filters
        for filter in VideoFilter.allCases {
            let item = NSMenuItem()
            item.title = filter.rawValue
            item.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: filter.rawValue)
            item.target = self
            item.action = #selector(filterSelected(_:))
            item.representedObject = filter

            if filter == videoState?.activeFilter {
                item.state = .on
            }

            menu.addItem(item)
        }

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

    @objc private func filterSelected(_ sender: NSMenuItem) {
        guard let filter = sender.representedObject as? VideoFilter else { return }
        videoState?.activeFilter = filter
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
        return "Filter: \(videoState?.activeFilter.rawValue ?? "None")"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .button
    }
}
