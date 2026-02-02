import Cocoa
import Combine

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
    private var timelineSlider: NSSlider?
    private var opacitySlider: NSSlider?
    private var volumeSlider: NSSlider?

    // Text fields
    private var frameField: NSTextField?
    private var frameTotalLabel: NSTextField?
    private var zoomField: NSTextField?
    private var zoomPercentLabel: NSTextField?
    private var opacityField: NSTextField?

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()
    private var isHovering = false
    private var isScrubbing = false
    private var firstResponderObserver: Any?
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
        let button = FilterMenuButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Replace the opacity icon with the filter button in the stack view
        stackView.removeArrangedSubview(icon)
        icon.removeFromSuperview()
        stackView.insertArrangedSubview(button, at: index)

        filterMenuButton = button
        filterMenuButton?.setAccessibilityIdentifier("button-filter-menu")
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
        firstResponderObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOpacity()
        }
    }

    deinit {
        if let observer = firstResponderObserver {
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
        guard let slider = timelineSlider else { return }
        handleTimelineChange(value: slider.doubleValue, isHighlighted: slider.isHighlighted)
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

    private func handleTimelineChange(value: Double, isHighlighted: Bool) {
        guard let state = videoState else { return }

        let wasScrubbing = isScrubbing
        isScrubbing = isHighlighted
        if isScrubbing {
            state.requestSeek(time: value, accurate: false)
            return
        }

        // On release (or click), do an accurate seek
        if wasScrubbing || !isHighlighted {
            state.requestSeek(time: value, accurate: true)
        }
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
            }
            .store(in: &cancellables)

        // Update frame field and total
        state.$currentFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.frameField?.stringValue = "\(frame)"
            }
            .store(in: &cancellables)

        state.$totalFrames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] total in
                self?.frameTotalLabel?.stringValue = "/ \(total)"
            }
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
            }
            .store(in: &cancellables)

        state.$opacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] opacity in
                guard let self = self, self.videoState?.quickFilter == nil else { return }
                self.opacityField?.stringValue = "\(Int(opacity * 100))"
                self.opacitySlider?.doubleValue = opacity
            }
            .store(in: &cancellables)

        // Update timeline slider maxValue when duration changes (ALWAYS update, even when scrubbing)
        state.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self = self else { return }
                self.timelineSlider?.maxValue = max(0.1, duration)
            }
            .store(in: &cancellables)

        // Update timeline slider position (only when not scrubbing)
        state.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTime in
                guard let self = self, !self.isScrubbing else { return }
                self.timelineSlider?.doubleValue = currentTime
            }
            .store(in: &cancellables)

        // Update mute button state - HIDE volume slider when muted
        state.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isMuted in
                self?.muteButton?.state = isMuted ? .on : .off
                self?.volumeSlider?.isHidden = isMuted
            }
            .store(in: &cancellables)

        // Update volume slider
        state.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.volumeSlider?.doubleValue = Double(volume)
            }
            .store(in: &cancellables)

        // Update lock button state
        state.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked in
                self?.lockButton?.state = isLocked ? .on : .off
                self?.lockButton?.contentTintColor = isLocked ? .systemRed : nil
                self?.zoomField?.isEnabled = !isLocked
                self?.resetButton?.isEnabled = !isLocked
                self?.updateOpacity()
            }
            .store(in: &cancellables)

        // Update enabled state based on video loaded
        state.$isVideoLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loaded in
                self?.stepBackButton?.isEnabled = loaded
                self?.playButton?.isEnabled = loaded
                self?.stepForwardButton?.isEnabled = loaded
                self?.timelineSlider?.isEnabled = loaded
                self?.frameField?.isEnabled = loaded
                self?.zoomField?.isEnabled = loaded && !(self?.videoState?.isLocked ?? false)
                self?.opacityField?.isEnabled = loaded
                self?.opacitySlider?.isEnabled = loaded
                self?.updateOpacity()
                if let filter = self?.videoState?.quickFilter {
                    self?.updateSliderForQuickFilter(filter)
                } else {
                    self?.updateSliderForQuickFilter(nil)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Quick Filter Slider

    private func updateSliderForQuickFilter(_ filter: VideoFilter?) {
        guard let state = videoState else { return }

        if let filter = filter {
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
            } else {
                opacitySlider?.isEnabled = false
                opacityField?.isEnabled = state.isVideoLoaded
                opacityField?.isEditable = false
                opacityField?.isSelectable = false
                opacitySlider?.doubleValue = 1.0
                opacityField?.stringValue = "On"
            }
        } else {
            // No quick filter: slider controls opacity (0-100%)
            opacitySlider?.minValue = 0.02  // Minimum 2%
            opacitySlider?.maxValue = 1.0
            opacitySlider?.doubleValue = state.opacity
            opacityField?.stringValue = "\(Int(state.opacity * 100))"
            opacitySlider?.isEnabled = state.isVideoLoaded
            opacityField?.isEnabled = state.isVideoLoaded
            opacityField?.isEditable = state.isVideoLoaded
            opacityField?.isSelectable = state.isVideoLoaded
        }
    }

    /// Format filter value for display based on filter's actual parameter range
    private func formatFilterValue(filter: VideoFilter, normalizedValue: Double) -> String {
        let range = filter.parameterRange
        let actualValue = range.min + (normalizedValue * (range.max - range.min))

        // Format based on the range
        if range.min < 0 {
            // Signed value (e.g., -1 to +1, -3 to +3)
            if actualValue >= 0 {
                return String(format: "+%.1f", actualValue)
            } else {
                return String(format: "%.1f", actualValue)
            }
        } else if range.max <= 2 {
            // Small range, show one decimal
            return String(format: "%.1f", actualValue)
        } else {
            // Larger range, show integer
            return "\(Int(actualValue.rounded()))"
        }
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
        // Check if any of our text fields currently has focus
        let fieldHasFocus = isTextFieldActive()

        // Show full opacity when: hovering, field focused, or no video loaded
        // Lock mode should NOT affect toolbar visibility
        let shouldShow = isHovering || fieldHasFocus || !(videoState?.isVideoLoaded ?? false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = shouldShow ? 1.0 : 0.4
        }
    }

    /// Check if any of our text fields is currently the first responder (being edited)
    private func isTextFieldActive() -> Bool {
        guard let window = self.window else { return false }
        guard let firstResponder = window.firstResponder else { return false }

        // When editing a text field, the first responder is the field editor (NSTextView)
        // We need to check if this field editor belongs to one of our fields
        if let textView = firstResponder as? NSTextView,
           let delegate = textView.delegate as? NSTextField {
            return delegate === frameField || delegate === zoomField || delegate === opacityField
        }

        // Also check if the field itself is first responder (before editing starts)
        if let textField = firstResponder as? NSTextField {
            return textField === frameField || textField === zoomField || textField === opacityField
        }

        return false
    }
}

// MARK: - NSTextFieldDelegate

extension ControlBar: NSTextFieldDelegate {

    func controlTextDidBeginEditing(_ obj: Notification) {
        updateOpacity()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Delay opacity update to allow first responder to change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateOpacity()
        }

        guard let textField = obj.object as? NSTextField else { return }

        if textField === frameField {
            if let value = Int(textField.stringValue) {
                videoState?.requestSeek(frame: value)
            }
        } else if textField === zoomField {
            if let value = Double(textField.stringValue) {
                videoState?.setZoomPercentage(value)
            }
        } else if textField === opacityField {
            // If quick filter active, parse as actual parameter value
            // Otherwise parse as opacity percentage
            if let filter = videoState?.quickFilter {
                guard filter.isQuickFilterAdjustable else { return }
                if let actualValue = Double(textField.stringValue) {
                    let range = filter.parameterRange
                    // Convert actual value to normalized 0-1
                    let normalized = (actualValue - range.min) / (range.max - range.min)
                    videoState?.quickFilterValue = max(0, min(1, normalized))
                }
            } else {
                if let value = Int(textField.stringValue) {
                    videoState?.setOpacityPercentage(value)
                }
            }
        }
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
                if let current = Int(textField.stringValue) {
                    let maxFrame = videoState?.totalFrames ?? 1
                    let newValue = max(0, min(maxFrame - 1, current + step * Int(direction)))
                    textField.stringValue = "\(newValue)"
                    videoState?.requestSeek(frame: newValue)
                }
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
                if let current = Double(textField.stringValue) {
                    let newValue = max(10, min(1000, current + step * direction))
                    // Show decimals when using fine control (cmd), otherwise integer
                    if cmd {
                        textField.stringValue = String(format: "%.1f", newValue)
                    } else if newValue.truncatingRemainder(dividingBy: 1) == 0 {
                        textField.stringValue = "\(Int(newValue))"
                    } else {
                        textField.stringValue = String(format: "%.1f", newValue)
                    }
                    videoState?.setZoomPercentage(newValue)
                }
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
