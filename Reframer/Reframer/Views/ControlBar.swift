import Cocoa
import Combine

/// Reports a complete mouse-tracking lifecycle while leaving keyboard and
/// accessibility actions as discrete exact seeks.
final class TimelineSlider: NSSlider {
    var onBeginTracking: (() -> Void)?
    var onEndTracking: ((Double) -> Void)?
    private(set) var isTrackingTimeline = false

    override func mouseDown(with event: NSEvent) {
        isTrackingTimeline = true
        onBeginTracking?()
        super.mouseDown(with: event)
        isTrackingTimeline = false
        onEndTracking?(doubleValue)
    }
}

/// A dedicated grip for moving the main overlay window from its attached
/// control window. Keeping this as an arranged view means its hit region can
/// never cover playback controls.
final class WindowDragHandle: NSView {
    weak var targetWindow: NSWindow?

    var isDragEnabled = true {
        didSet {
            guard oldValue != isDragEnabled else { return }
            updatePresentation()
            window?.invalidateCursorRects(for: self)
        }
    }

    private let gripImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        gripImageView.translatesAutoresizingMaskIntoConstraints = false
        gripImageView.image = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: nil
        )
        gripImageView.imageScaling = .scaleProportionallyDown
        gripImageView.setAccessibilityElement(false)
        addSubview(gripImageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 32),
            gripImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            gripImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            gripImageView.widthAnchor.constraint(equalToConstant: 15),
            gripImageView.heightAnchor.constraint(equalToConstant: 15)
        ])

        identifier = NSUserInterfaceItemIdentifier("window-drag-handle")
        setAccessibilityIdentifier("window-drag-handle")
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel("Move overlay window")
        updatePresentation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePresentation()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isDragEnabled ? .openHand : .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        guard isDragEnabled,
              event.type == .leftMouseDown,
              let windowToMove = targetWindow ?? window?.parent else {
            return
        }

        window?.makeFirstResponder(self)
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        windowToMove.performDrag(with: event)
    }

    private func updatePresentation() {
        gripImageView.contentTintColor = isDragEnabled
            ? .secondaryLabelColor
            : .disabledControlTextColor
        layer?.backgroundColor = (
            isDragEnabled
                ? NSColor.labelColor.withAlphaComponent(0.07)
                : NSColor.clear
        ).cgColor
        toolTip = isDragEnabled
            ? "Drag to move the overlay window"
            : "Unlock the overlay before moving it"
        setAccessibilityHelp(toolTip)
        setAccessibilityValue(isDragEnabled ? "Available" : "Disabled while locked")
        setAccessibilityEnabled(isDragEnabled)
    }
}

/// Pure AppKit control bar loaded from XIB
class ControlBar: NSView {

    // MARK: - Controls (found programmatically)

    private var visualEffectView: NSVisualEffectView?
    private var mainStackView: NSStackView?

    // Buttons
    private var openButton: NSButton?
    private var stepBackButton: NSButton?
    private var playButton: NSButton?
    private var stepForwardButton: NSButton?
    private var resetButton: NSButton?
    private var muteButton: NSButton?
    private var lockButton: NSButton?

    // Filter menu button (replaces opacity icon)
    private var filterMenuButton: FilterMenuButton?
    private var opacityIcon: NSImageView?

    // Sliders
    private var timelineSlider: TimelineSlider?
    private var opacitySlider: NSSlider?
    private var volumeSlider: NSSlider?

    // Text fields
    private var frameField: NSTextField?
    private var frameTotalLabel: NSTextField?
    private var zoomField: NSTextField?
    private var zoomPercentLabel: NSTextField?
    private var opacityField: NSTextField?
    private var windowDragHandle: WindowDragHandle?

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    weak var windowToDrag: NSWindow? {
        didSet { windowDragHandle?.targetWindow = windowToDrag }
    }

    private var cancellables = Set<AnyCancellable>()
    private var isHovering = false
    private var focusObservers: [NSObjectProtocol] = []
    enum StepCommand {
        case up
        case down
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadFromNib()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadFromNib()
    }

    private func loadFromNib() {
        // Load the XIB without using outlet connections
        var topLevelObjects: NSArray?
        let bundle = Bundle(for: type(of: self))
        guard bundle.loadNibNamed("ControlBar", owner: nil, topLevelObjects: &topLevelObjects) else {
            fatalError("Failed to load ControlBar.xib")
        }

        // Find the main view from the XIB
        guard let objects = topLevelObjects,
              let contentView = objects.compactMap({ $0 as? NSView }).first else {
            fatalError("Could not find content view in ControlBar.xib")
        }

        // Add the loaded view as a subview with PROPER Auto Layout constraints
        // The XIB has hardcoded width (861px) so we must use constraints to force it to match our bounds
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Find controls by their XIB identifiers
        findControls(in: contentView)

        // The XIB has fixed-width constraints (priority 1000) on sliders totaling ~861px
        // We need to lower their priority so they can compress to fit 800px
        makeSliderWidthsFlexible()

        // Apply bottom corner radius to match main window's corner radius
        applyCornerRadius()

        // Replace opacity icon with FilterMenuButton
        setupFilterButton()
        setupWindowDragHandle()

        setupActions()
        setupTextFieldDelegates()
        setupTrackingArea()
    }

    private func findControls(in view: NSView) {
        // Find by identifier (matches XIB id attribute)
        func find<T: NSView>(_ id: String) -> T? {
            return findView(withIdentifier: id, in: view) as? T
        }

        visualEffectView = find("glass-bg")
        mainStackView = find("main-stack")

        openButton = find("btn-open")
        stepBackButton = find("btn-step-back")
        playButton = find("btn-play")
        stepForwardButton = find("btn-step-forward")
        resetButton = find("btn-reset")
        muteButton = find("btn-mute")
        lockButton = find("btn-lock")

        timelineSlider = find("slider-timeline")
        opacitySlider = find("slider-opacity")
        volumeSlider = find("slider-volume")

        frameField = find("field-frame")
        frameTotalLabel = find("label-frame-total")
        zoomField = find("field-zoom")
        zoomPercentLabel = find("label-zoom-pct")
        opacityField = find("field-opacity")
        opacityIcon = find("icon-opacity")

        // Set accessibility identifiers for UI testing
        // Regular buttons
        openButton?.setAccessibilityIdentifier("button-open")
        stepBackButton?.setAccessibilityIdentifier("button-step-backward")
        stepForwardButton?.setAccessibilityIdentifier("button-step-forward")
        resetButton?.setAccessibilityIdentifier("button-reset")

        // Toggle buttons need setAccessibilityElement to be visible to XCUITest
        playButton?.setAccessibilityIdentifier("button-play")
        playButton?.setAccessibilityElement(true)
        playButton?.setAccessibilityRole(.button)

        muteButton?.setAccessibilityIdentifier("button-mute")
        muteButton?.setAccessibilityElement(true)
        muteButton?.setAccessibilityRole(.button)

        lockButton?.setAccessibilityIdentifier("button-lock")
        lockButton?.setAccessibilityElement(true)
        lockButton?.setAccessibilityRole(.button)

        // Sliders and fields
        timelineSlider?.setAccessibilityIdentifier("slider-timeline")
        opacitySlider?.setAccessibilityIdentifier("slider-opacity")
        volumeSlider?.setAccessibilityIdentifier("slider-volume")
        frameField?.setAccessibilityIdentifier("input-frame")
        zoomField?.setAccessibilityIdentifier("input-zoom")
        opacityField?.setAccessibilityIdentifier("input-opacity")

        configureAccessibility()
    }

    private func configureAccessibility() {
        configure(button: openButton, label: "Open video", help: "Choose an MP4, M4V, or MOV video")
        configure(button: stepBackButton, label: "Previous frame", help: "Step backward one decoded video frame")
        configure(button: playButton, label: "Play", help: "Start or pause video playback")
        configure(button: stepForwardButton, label: "Next frame", help: "Step forward one decoded video frame")
        configure(button: resetButton, label: "Reset view", help: "Reset zoom and position")
        configure(button: muteButton, label: "Mute", help: "Mute or unmute video audio")
        configure(button: lockButton, label: "Lock overlay", help: "Lock or unlock global frame stepping")

        configure(control: timelineSlider, label: "Timeline", help: "Scrub through the video")
        configure(control: opacitySlider, label: "Opacity", help: "Adjust video opacity")
        configure(control: volumeSlider, label: "Volume", help: "Adjust playback volume")
        configure(control: frameField, label: "Current frame", help: "Enter a decoded frame number")
        configure(control: zoomField, label: "Zoom percentage", help: "Enter a zoom from 10 to 1000 percent")
        configure(control: opacityField, label: "Opacity percentage", help: "Enter opacity from 2 to 100 percent")

        frameTotalLabel?.setAccessibilityElement(false)
        zoomPercentLabel?.setAccessibilityElement(false)
    }

    private func configure(button: NSButton?, label: String, help: String) {
        button?.setAccessibilityElement(true)
        button?.setAccessibilityRole(.button)
        button?.setAccessibilityLabel(label)
        button?.setAccessibilityHelp(help)
        button?.toolTip = help
    }

    private func configure(control: NSControl?, label: String, help: String) {
        control?.setAccessibilityElement(true)
        control?.setAccessibilityLabel(label)
        control?.setAccessibilityHelp(help)
        control?.toolTip = help
    }

    private func findView(withIdentifier identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(withIdentifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }

    private func makeSliderWidthsFlexible() {
        // The XIB has fixed width constraints on sliders that prevent the toolbar from resizing
        // Lower their priority so the toolbar can compress to match the window width
        for slider in [timelineSlider, opacitySlider, volumeSlider] {
            guard let slider = slider else { continue }
            for constraint in slider.constraints {
                if constraint.firstAttribute == .width {
                    // Lower priority from required (1000) to high (750) so it can be compressed
                    constraint.priority = NSLayoutConstraint.Priority(rawValue: 250)
                }
            }
            // Also lower compression resistance so the slider can shrink
            slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }

    private func applyCornerRadius() {
        // Only round BOTTOM corners - top edge aligns with main window's bottom
        // In macOS coordinates (y=0 at bottom):
        // .layerMinXMinYCorner = bottom-left, .layerMaxXMinYCorner = bottom-right
        visualEffectView?.wantsLayer = true
        visualEffectView?.layer?.cornerRadius = 12
        visualEffectView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        visualEffectView?.layer?.masksToBounds = true
    }

    private func setupFilterButton() {
        guard let stackView = mainStackView,
              let icon = opacityIcon,
              let index = stackView.arrangedSubviews.firstIndex(of: icon) else { return }

        // Create the filter menu button
        let button = FilterMenuButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])

        // Replace the opacity icon with the filter button in the stack view
        stackView.removeArrangedSubview(icon)
        icon.removeFromSuperview()
        stackView.insertArrangedSubview(button, at: index)

        filterMenuButton = button
        filterMenuButton?.setAccessibilityIdentifier("button-filter-menu")
    }

    private func setupWindowDragHandle() {
        guard let stackView = mainStackView else { return }
        let handle = WindowDragHandle(frame: NSRect(x: 0, y: 0, width: 24, height: 32))
        handle.targetWindow = windowToDrag
        stackView.insertArrangedSubview(handle, at: 0)
        windowDragHandle = handle
    }

    // MARK: - Actions Setup

    private func setupActions() {
        openButton?.target = self
        openButton?.action = #selector(openClicked)

        stepBackButton?.target = self
        stepBackButton?.action = #selector(stepBackClicked)

        playButton?.target = self
        playButton?.action = #selector(playClicked)

        stepForwardButton?.target = self
        stepForwardButton?.action = #selector(stepForwardClicked)

        resetButton?.target = self
        resetButton?.action = #selector(resetClicked)

        muteButton?.target = self
        muteButton?.action = #selector(muteClicked)

        lockButton?.target = self
        lockButton?.action = #selector(lockClicked)

        timelineSlider?.target = self
        timelineSlider?.action = #selector(timelineChanged)
        timelineSlider?.onBeginTracking = { [weak self] in
            self?.videoState?.beginScrubbing()
        }
        timelineSlider?.onEndTracking = { [weak self] value in
            self?.videoState?.endScrubbing(time: value)
        }

        opacitySlider?.target = self
        opacitySlider?.action = #selector(opacitySliderChanged)

        volumeSlider?.target = self
        volumeSlider?.action = #selector(volumeSliderChanged)
    }

    private func setupTextFieldDelegates() {
        frameField?.delegate = self
        zoomField?.delegate = self
        opacityField?.delegate = self
    }

    private func setupTrackingArea() {
        updateTrackingAreas()

        // Observe first responder changes to update opacity when fields gain/lose focus
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object as? NSWindow === self?.window else { return }
                self?.updateOpacity()
            }
            focusObservers.append(observer)
        }
    }

    deinit {
        for observer in focusObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func updateTrackingAreas() {
        // Remove existing tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        // Add new tracking area
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        super.updateTrackingAreas()
    }

    // MARK: - IBActions

    @objc private func openClicked(_ sender: Any?) {
        NotificationCenter.default.post(name: .openVideo, object: nil)
    }

    @objc private func stepBackClicked(_ sender: Any?) {
        videoState?.requestFrameStep(direction: .backward, amount: 1)
    }

    @objc private func playClicked(_ sender: Any?) {
        videoState?.isPlaying.toggle()
    }

    @objc private func stepForwardClicked(_ sender: Any?) {
        videoState?.requestFrameStep(direction: .forward, amount: 1)
    }

    @objc private func resetClicked(_ sender: Any?) {
        videoState?.resetView()
    }

    @objc private func muteClicked(_ sender: Any?) {
        videoState?.toggleMute()
    }

    @objc private func lockClicked(_ sender: Any?) {
        videoState?.isLocked.toggle()
    }

    @objc private func timelineChanged(_ sender: Any?) {
        guard let slider = timelineSlider, let state = videoState else { return }
        if slider.isTrackingTimeline {
            state.previewScrub(time: slider.doubleValue)
        } else {
            state.requestSeek(time: slider.doubleValue, accurate: true)
        }
    }

    @objc private func opacitySliderChanged(_ sender: Any?) {
        guard let slider = opacitySlider, let state = videoState else { return }

        // If quick filter is active, control the filter value; otherwise control opacity
        if state.quickFilter != nil {
            if state.quickFilter?.isQuickFilterAdjustable == false {
                return
            }
            state.quickFilterValue = slider.doubleValue
        } else {
            state.opacity = slider.doubleValue
        }
    }

    @objc private func volumeSliderChanged(_ sender: Any?) {
        guard let slider = volumeSlider else { return }
        videoState?.volume = Float(slider.doubleValue)
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        // Pass state to filter button
        filterMenuButton?.videoState = state

        // Update play button state
        state.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.playButton?.state = isPlaying ? .on : .off
                self?.playButton?.setAccessibilityLabel(isPlaying ? "Pause" : "Play")
                self?.playButton?.setAccessibilityValue(isPlaying ? "Playing" : "Paused")
                self?.playButton?.toolTip = isPlaying ? "Pause video playback" : "Play video"
            }
            .store(in: &cancellables)

        // Update frame field and total
        state.$currentFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.frameField?.stringValue = "\(frame)"
                self?.frameField?.setAccessibilityValue(frame)
            }
            .store(in: &cancellables)

        state.$totalFrames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFrameNavigationPresentation() }
            .store(in: &cancellables)

        state.$frameNavigationPrecision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFrameNavigationPresentation() }
            .store(in: &cancellables)

        state.$frameNavigationMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFrameNavigationPresentation() }
            .store(in: &cancellables)

        // Update zoom field
        state.$zoomScale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scale in
                let percentage = scale * 100
                // Show decimals only if present, otherwise show integer
                if percentage.truncatingRemainder(dividingBy: 1) == 0 {
                    self?.zoomField?.stringValue = "\(Int(percentage))"
                } else {
                    self?.zoomField?.stringValue = String(format: "%.1f", percentage)
                }
                self?.zoomField?.setAccessibilityValue(percentage)
            }
            .store(in: &cancellables)

        // Update opacity/filter slider based on whether quick filter is active
        // When quick filter is active: slider controls filter value (0-1)
        // When no quick filter: slider controls opacity

        state.$quickFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] filter in
                self?.updateSliderForQuickFilter(filter)
            }
            .store(in: &cancellables)

        state.$quickFilterValue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self = self,
                      let filter = self.videoState?.quickFilter else { return }
                guard filter.isQuickFilterAdjustable else { return }
                self.opacitySlider?.doubleValue = value
                self.opacityField?.stringValue = self.formatFilterValue(filter: filter, normalizedValue: value)
                self.opacitySlider?.setAccessibilityValue(value)
                self.opacityField?.setAccessibilityValue(self.opacityField?.stringValue)
            }
            .store(in: &cancellables)

        state.$opacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] opacity in
                guard let self = self, self.videoState?.quickFilter == nil else { return }
                self.opacityField?.stringValue = "\(Int(opacity * 100))"
                self.opacitySlider?.doubleValue = opacity
                self.opacityField?.setAccessibilityValue(Int(opacity * 100))
                self.opacitySlider?.setAccessibilityValue(opacity)
            }
            .store(in: &cancellables)

        // Update timeline slider maxValue when duration changes (ALWAYS update, even when scrubbing)
        state.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self = self else { return }
                self.timelineSlider?.maxValue = max(0.1, duration)
                self.timelineSlider?.setAccessibilityMaxValue(duration)
            }
            .store(in: &cancellables)

        // Update timeline slider position (only when not scrubbing)
        state.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime in
                guard let self = self, self.videoState?.isScrubbing != true else { return }
                self.timelineSlider?.doubleValue = currentTime
                self.timelineSlider?.setAccessibilityValue(currentTime)
            }
            .store(in: &cancellables)

        // Update mute button state - HIDE volume slider when muted
        state.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMuted in
                self?.muteButton?.state = isMuted ? .on : .off
                self?.volumeSlider?.isHidden = isMuted
                self?.muteButton?.setAccessibilityLabel(isMuted ? "Unmute" : "Mute")
                self?.muteButton?.setAccessibilityValue(isMuted ? "Muted" : "Audible")
                self?.muteButton?.toolTip = isMuted ? "Unmute video audio" : "Mute video audio"
            }
            .store(in: &cancellables)

        // Update volume slider
        state.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.volumeSlider?.doubleValue = Double(volume)
                self?.volumeSlider?.setAccessibilityValue(volume)
            }
            .store(in: &cancellables)

        // Update lock button state
        state.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked in
                self?.windowDragHandle?.isDragEnabled = !isLocked
                self?.lockButton?.state = isLocked ? .on : .off
                self?.lockButton?.contentTintColor = isLocked ? .systemRed : nil
                self?.lockButton?.setAccessibilityLabel(isLocked ? "Unlock overlay" : "Lock overlay")
                self?.lockButton?.setAccessibilityValue(isLocked ? "Locked" : "Unlocked")
                self?.lockButton?.toolTip = isLocked ? "Unlock global frame stepping" : "Lock and enable global frame stepping"
                self?.zoomField?.isEnabled = !isLocked
                self?.resetButton?.isEnabled = !isLocked
                self?.updateOpacity()
            }
            .store(in: &cancellables)

        // Update enabled state based on video loaded
        state.$isVideoLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loaded in
                self?.playButton?.isEnabled = loaded
                self?.timelineSlider?.isEnabled = loaded
                self?.zoomField?.isEnabled = loaded && !(self?.videoState?.isLocked ?? false)
                self?.opacityField?.isEnabled = loaded
                self?.opacitySlider?.isEnabled = loaded
                self?.updateFrameNavigationPresentation()
                self?.updateOpacity()
                if let filter = self?.videoState?.quickFilter {
                    self?.updateSliderForQuickFilter(filter)
                } else {
                    self?.updateSliderForQuickFilter(nil)
                }
            }
            .store(in: &cancellables)
    }

    private func updateFrameNavigationPresentation() {
        guard let state = videoState else { return }
        let supportsFrames = state.isVideoLoaded
            && state.totalFrames > 0
            && state.frameNavigationPrecision.supportsFrameNavigation
        stepBackButton?.isEnabled = supportsFrames
        stepForwardButton?.isEnabled = supportsFrames
        frameField?.isEnabled = supportsFrames

        let suffix: String
        let help: String
        switch state.frameNavigationPrecision {
        case .exact:
            suffix = "/ \(state.totalFrames)"
            help = "Current decoded frame. Video contains \(state.totalFrames) exact presentation frames."
        case .indexing:
            suffix = state.totalFrames > 0 ? "/ ~\(state.totalFrames) · indexing" : "/ indexing"
            help = state.frameNavigationMessage
                ?? "Exact frame boundaries are being indexed. The current frame count is estimated."
        case .estimated:
            suffix = state.totalFrames > 0 ? "/ ~\(state.totalFrames)" : "/ —"
            help = state.frameNavigationMessage
                ?? "Exact frame boundaries are unavailable. Frame numbers are estimated."
        case .unavailable:
            suffix = "/ —"
            help = state.frameNavigationMessage
                ?? "Frame navigation is unavailable for this video. Time-based playback remains available."
        }
        frameTotalLabel?.stringValue = suffix
        frameField?.setAccessibilityHelp(help)
        frameField?.toolTip = help
        frameTotalLabel?.toolTip = help
    }

    // MARK: - Quick Filter Slider

    private func updateSliderForQuickFilter(_ filter: VideoFilter?) {
        guard let state = videoState else { return }

        if let filter = filter {
            opacitySlider?.setAccessibilityLabel("\(filter.rawValue) strength")
            opacitySlider?.setAccessibilityHelp("Adjust the \(filter.rawValue.lowercased()) quick filter")
            opacityField?.setAccessibilityLabel("\(filter.rawValue) value")
            // Quick filter active: slider controls filter value (0-1 normalized)
            // But display shows actual parameter value
            opacitySlider?.minValue = 0.0
            opacitySlider?.maxValue = 1.0
            if filter.isQuickFilterAdjustable {
                opacitySlider?.isEnabled = state.isVideoLoaded
                opacityField?.isEnabled = state.isVideoLoaded
                opacityField?.isEditable = state.isVideoLoaded
                opacityField?.isSelectable = state.isVideoLoaded
                opacitySlider?.doubleValue = state.quickFilterValue
                opacityField?.stringValue = formatFilterValue(filter: filter, normalizedValue: state.quickFilterValue)
                if let opacityField {
                    restoreAccessibilityHelp(for: opacityField)
                }
            } else {
                opacitySlider?.isEnabled = false
                opacityField?.isEnabled = state.isVideoLoaded
                opacityField?.isEditable = false
                opacityField?.isSelectable = false
                opacitySlider?.doubleValue = 1.0
                opacityField?.stringValue = "On"
            }
        } else {
            opacitySlider?.setAccessibilityLabel("Opacity")
            opacitySlider?.setAccessibilityHelp("Adjust video opacity")
            opacityField?.setAccessibilityLabel("Opacity percentage")
            // No quick filter: slider controls opacity (0-100%)
            opacitySlider?.minValue = 0.02  // Minimum 2%
            opacitySlider?.maxValue = 1.0
            opacitySlider?.doubleValue = state.opacity
            opacityField?.stringValue = "\(Int(state.opacity * 100))"
            opacitySlider?.isEnabled = state.isVideoLoaded
            opacityField?.isEnabled = state.isVideoLoaded
            opacityField?.isEditable = state.isVideoLoaded
            opacityField?.isSelectable = state.isVideoLoaded
            if let opacityField {
                restoreAccessibilityHelp(for: opacityField)
            }
        }
    }

    /// Format filter value for display based on filter's actual parameter range
    private func formatFilterValue(filter: VideoFilter, normalizedValue: Double) -> String {
        let range = filter.parameterRange
        let actualValue = range.min + (normalizedValue * (range.max - range.min))
        return NumericTextInput.canonical(
            actualValue,
            fractionDigits: filterInputFractionDigits(filter)
        )
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateOpacity()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateOpacity()
    }

    private func updateOpacity() {
        let accessibilityIsActive = NSWorkspace.shared.isVoiceOverEnabled
        let shouldShow = isHovering ||
            isControlBarFocused() ||
            accessibilityIsActive ||
            !(videoState?.isVideoLoaded ?? false)
        let targetAlpha: CGFloat = shouldShow ? 1.0 : 0.4

        guard abs(alphaValue - targetAlpha) > 0.001 else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            self.animator().alphaValue = targetAlpha
        }
    }

    /// Keep controls legible whenever keyboard focus is anywhere in the bar.
    private func isControlBarFocused() -> Bool {
        guard let window = self.window else { return false }
        guard let firstResponder = window.firstResponder else { return false }

        if let textView = firstResponder as? NSTextView,
           let delegate = textView.delegate as? NSTextField {
            return delegate === frameField ||
                delegate === zoomField ||
                delegate === opacityField ||
                delegate.isDescendant(of: self)
        }

        if let view = firstResponder as? NSView {
            return view === self || view.isDescendant(of: self)
        }

        return false
    }
}

// MARK: - NSTextFieldDelegate

extension ControlBar: NSTextFieldDelegate {

    func controlTextDidBeginEditing(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            restoreAccessibilityHelp(for: textField)
        }
        updateOpacity()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Delay opacity update to allow first responder to change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateOpacity()
        }

        guard let textField = obj.object as? NSTextField else { return }

        if textField === frameField {
            let lastFrame = max(0, (videoState?.totalFrames ?? 1) - 1)
            let result = NumericTextInput.integer(
                textField.stringValue,
                current: videoState?.currentFrame ?? 0,
                range: 0...lastFrame,
                fieldName: "Frame"
            )
            if case .accepted(let value, _) = apply(
                result,
                to: textField
            ) {
                videoState?.requestSeek(frame: Int(value))
            }
        } else if textField === zoomField {
            let result = NumericTextInput.decimal(
                textField.stringValue,
                current: videoState?.zoomPercentageValue ?? 100,
                range: 10...1_000,
                fractionDigits: 1,
                fieldName: "Zoom"
            )
            if case .accepted(let value, _) = apply(result, to: textField) {
                videoState?.setZoomPercentage(value)
            }
        } else if textField === opacityField {
            // If quick filter active, parse as actual parameter value
            // Otherwise parse as opacity percentage
            if let filter = videoState?.quickFilter {
                guard filter.isQuickFilterAdjustable else { return }
                let range = filter.parameterRange
                let current = range.min
                    + ((videoState?.quickFilterValue ?? filter.defaultNormalizedValue)
                       * (range.max - range.min))
                let result = NumericTextInput.decimal(
                    textField.stringValue,
                    current: current,
                    range: range.min...range.max,
                    fractionDigits: filterInputFractionDigits(filter),
                    fieldName: "\(filter.rawValue) value"
                )
                if case .accepted(let actualValue, _) = apply(result, to: textField) {
                    // Convert actual value to normalized 0-1
                    let normalized = (actualValue - range.min) / (range.max - range.min)
                    videoState?.quickFilterValue = max(0, min(1, normalized))
                }
            } else {
                let result = NumericTextInput.decimal(
                    textField.stringValue,
                    current: videoState?.opacityPercentageValue ?? 100,
                    range: 2...100,
                    fractionDigits: 1,
                    fieldName: "Opacity"
                )
                if case .accepted(let value, _) = apply(result, to: textField) {
                    videoState?.setOpacityPercentage(value)
                }
            }
        }
    }

    @discardableResult
    private func apply(
        _ result: NumericTextResult,
        to textField: NSTextField
    ) -> NumericTextResult {
        switch result {
        case .accepted(_, let canonical):
            textField.stringValue = canonical
            textField.setAccessibilityValue(canonical)
            restoreAccessibilityHelp(for: textField)
        case .rejected(let canonical, let message):
            textField.stringValue = canonical
            textField.setAccessibilityValue(canonical)
            textField.setAccessibilityHelp(message)
            textField.toolTip = message
            NSAccessibility.post(element: textField, notification: .valueChanged)
            NSSound.beep()
        }
        return result
    }

    private func restoreAccessibilityHelp(for textField: NSTextField) {
        if textField === frameField {
            updateFrameNavigationPresentation()
        } else if textField === zoomField {
            textField.setAccessibilityHelp("Enter a finite zoom from 10 to 1000 percent")
            textField.toolTip = textField.accessibilityHelp()
        } else if textField === opacityField, let filter = videoState?.quickFilter {
            textField.setAccessibilityHelp(
                "Enter a finite \(filter.rawValue.lowercased()) value from \(NumericTextInput.canonical(filter.parameterRange.min, fractionDigits: filterInputFractionDigits(filter))) to \(NumericTextInput.canonical(filter.parameterRange.max, fractionDigits: filterInputFractionDigits(filter)))"
            )
            textField.toolTip = textField.accessibilityHelp()
        } else if textField === opacityField {
            textField.setAccessibilityHelp("Enter a finite opacity from 2 to 100 percent")
            textField.toolTip = textField.accessibilityHelp()
        }
    }

    private func filterInputFractionDigits(_ filter: VideoFilter) -> Int {
        2
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let textField = control as? NSTextField else { return false }

        if let stepCommand = Self.stepCommand(for: commandSelector) {
            let direction: Double = stepCommand == .up ? 1 : -1
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            let shift = flags.contains(.shift)
            let cmd = flags.contains(.command)
            let option = flags.contains(.option)
            let control = flags.contains(.control)
            let coarse = shift || option || control

            if textField === frameField {
                let step = coarse ? 10 : 1
                let maxFrame = max(0, (videoState?.totalFrames ?? 1) - 1)
                let parsed = Int(textField.stringValue)
                let current = parsed ?? videoState?.currentFrame ?? 0
                let (sum, overflowed) = current.addingReportingOverflow(step * Int(direction))
                let requested = overflowed ? (direction > 0 ? Int.max : Int.min) : sum
                let newValue = max(0, min(maxFrame, requested))
                textField.stringValue = "\(newValue)"
                videoState?.requestSeek(frame: newValue)
                return true
            } else if textField === zoomField {
                let step: Double
                if cmd {
                    step = 0.1
                } else if coarse {
                    step = 10
                } else {
                    step = 1
                }
                let parsed = Double(textField.stringValue)
                let current = parsed?.isFinite == true
                    ? parsed!
                    : videoState?.zoomPercentageValue ?? 100
                let newValue = max(10, min(1000, current + step * direction))
                textField.stringValue = NumericTextInput.canonical(newValue, fractionDigits: 1)
                videoState?.setZoomPercentage(newValue)
                return true
            } else if textField === opacityField {
                if let filter = videoState?.quickFilter {
                    guard filter.isQuickFilterAdjustable else { return true }
                    // Quick filter active: step by 1% of range normally, 10% with shift
                    let stepPercent = coarse ? 0.1 : 0.01
                    let normalizedStep = stepPercent * direction

                    let currentNormalized = videoState?.quickFilterValue ?? 0.5
                    let newNormalized = max(0, min(1, currentNormalized + normalizedStep))
                    videoState?.quickFilterValue = newNormalized
                    textField.stringValue = formatFilterValue(filter: filter, normalizedValue: newNormalized)
                } else {
                    // Opacity mode: step by percentage
                    let step = coarse ? 10 : 1
                    if let current = Int(textField.stringValue) {
                        let newValue = max(2, min(100, current + step * Int(direction)))
                        textField.stringValue = "\(newValue)"
                        videoState?.setOpacityPercentage(newValue)
                    }
                }
                return true
            }
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
           commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window?.makeFirstResponder(nil)
            return true
        }

        return false
    }

    static func stepCommand(for commandSelector: Selector) -> StepCommand? {
        let stepUpSelectors: [Selector] = [
            #selector(NSResponder.moveUp(_:)),
            #selector(NSResponder.moveUpAndModifySelection(_:)),
            #selector(NSResponder.moveToBeginningOfDocument(_:)),
            #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)),
            #selector(NSResponder.moveToBeginningOfParagraph(_:)),
            #selector(NSResponder.moveToBeginningOfParagraphAndModifySelection(_:))
        ]

        let stepDownSelectors: [Selector] = [
            #selector(NSResponder.moveDown(_:)),
            #selector(NSResponder.moveDownAndModifySelection(_:)),
            #selector(NSResponder.moveToEndOfDocument(_:)),
            #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)),
            #selector(NSResponder.moveToEndOfParagraph(_:)),
            #selector(NSResponder.moveToEndOfParagraphAndModifySelection(_:))
        ]

        if stepUpSelectors.contains(commandSelector) {
            return .up
        }
        if stepDownSelectors.contains(commandSelector) {
            return .down
        }
        return nil
    }
}
