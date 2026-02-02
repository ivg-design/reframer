import Cocoa
import Combine
import ApplicationServices
import WebKit

// Custom window that can become key
class TransparentWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Enable Cmd+M minimize for borderless windows
    override func performMiniaturize(_ sender: Any?) {
        miniaturize(sender)
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    override init() {
        super.init()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - Properties

    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    var mainWindow: TransparentWindow!
    private var controlWindow: TransparentWindow!
    private var shortcutsWindow: TransparentWindow?  // Keyboard shortcuts panel (H key)
    private var documentationWindow: NSWindow?        // Documentation browser (Help menu)
    private var documentationWebView: WKWebView?
    private var filterPanelWindow: TransparentWindow?

    let videoState = VideoState()
    private var cancellables = Set<AnyCancellable>()
    private let controlWindowHeight: CGFloat = 80
    private let windowFrameDefaultsKey = "VideoOverlay.mainWindowFrame"

    private var mainViewController: MainViewController!
    private var controlBar: ControlBar!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        createMainWindow()
        createControlWindow()
        observeWindowFrameChanges()
        setupGlobalShortcuts()
        observeState()

        // Skip move-to-Applications prompt (disabled for development)
        // ensureInstalledInApplications()

        // Auto-load test video if specified (for UI testing)
        if let testVideoPath = ProcessInfo.processInfo.environment["TEST_VIDEO_PATH"] {
            let url = URL(fileURLWithPath: testVideoPath)
            if FileManager.default.fileExists(atPath: testVideoPath) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.videoState.isVideoLoaded = false
                    self?.videoState.videoURL = url
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalShortcutMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localShortcutMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Handle files opened via "Open With" from Finder
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }

        // Check if it's a supported video format
        if VideoFormats.isSupported(url) {
            // Delay slightly to ensure windows are ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.videoState.isVideoLoaded = false
                self?.videoState.videoURL = url
            }
        } else {
            // Show error for unsupported formats
            showErrorAlert(title: "Unsupported Format",
                           message: "The file '\(url.lastPathComponent)' is not a supported video format.\n\nSupported formats: \(VideoFormats.displayString)")
        }
    }

    // MARK: - Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Reframer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Reframer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Reframer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open Video", action: #selector(openVideo(_:)), keyEquivalent: "o")

        // Edit menu (required for Cmd+V paste in text fields)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reset Zoom", action: #selector(resetZoom(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Reset Position", action: #selector(resetPosition(_:)), keyEquivalent: "r")
        viewMenu.addItem(.separator())
        let lockItem = NSMenuItem(title: "Toggle Lock", action: #selector(toggleLock(_:)), keyEquivalent: "L")
        lockItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(lockItem)

        // Filter menu (single selection like toolbar, simple filters only)
        let filterMenuItem = NSMenuItem()
        mainMenu.addItem(filterMenuItem)
        let filterMenu = NSMenu(title: "Filter")
        filterMenuItem.submenu = filterMenu
        filterMenu.delegate = self

        // Filter items will be populated dynamically via menu delegate
        filterMenu.addItem(withTitle: "Placeholder", action: nil, keyEquivalent: "")
        filterMenu.addItem(.separator())
        filterMenu.addItem(withTitle: "Advanced Filters...", action: #selector(showFilterSettings(_:)), keyEquivalent: "")
        filterMenu.addItem(.separator())
        filterMenu.addItem(withTitle: "Reset Filter Parameters", action: #selector(resetFilterSettings(_:)), keyEquivalent: "")

        // Playback menu
        let playbackMenuItem = NSMenuItem()
        mainMenu.addItem(playbackMenuItem)
        let playbackMenu = NSMenu(title: "Playback")
        playbackMenuItem.submenu = playbackMenu
        let playPauseItem = NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause(_:)), keyEquivalent: " ")
        playPauseItem.keyEquivalentModifierMask = [.command, .shift]
        playbackMenu.addItem(playPauseItem)
        playbackMenu.addItem(.separator())
        let stepForwardItem = NSMenuItem(title: "Step Forward", action: #selector(stepForward(_:)), keyEquivalent: "")
        stepForwardItem.keyEquivalentModifierMask = [.command]
        playbackMenu.addItem(stepForwardItem)
        let stepBackwardItem = NSMenuItem(title: "Step Backward", action: #selector(stepBackward(_:)), keyEquivalent: "")
        stepBackwardItem.keyEquivalentModifierMask = [.command]
        playbackMenu.addItem(stepBackwardItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(toggleMinimize(_:)), keyEquivalent: "m")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // Help menu - put documentation first since macOS may intercept first item
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "Reframer Documentation", action: #selector(openReframerHelp(_:)), keyEquivalent: "?")

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Window Creation

    private func createMainWindow() {
        // Get screen frame for proper centering
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Main window is just the video canvas - toolbar will be BELOW it
        let windowSize = NSSize(width: 800, height: 560)
        let defaultOrigin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2 + controlWindowHeight / 2
        )
        let defaultFrame = NSRect(origin: defaultOrigin, size: windowSize)
        let windowFrame = loadSavedWindowFrame(defaultFrame: defaultFrame, screenFrame: screenFrame)

        let window = TransparentWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        // Explicitly set frame for borderless window
        window.setFrame(windowFrame, display: false)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true  // Enable window dragging

        mainViewController = MainViewController(videoState: videoState)
        window.contentViewController = mainViewController

        // Set frame again after content view controller to ensure size
        window.setFrame(windowFrame, display: true)

        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        mainWindow = window
    }

    private func createControlWindow() {
        let mainFrame = mainWindow.frame
        // Position toolbar BELOW the main window (flush against bottom edge)
        let controlFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY - controlWindowHeight,
            width: mainFrame.width,
            height: controlWindowHeight
        )

        let window = TransparentWindow(
            contentRect: controlFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = mainWindow.level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // NOTE: Do NOT set isMovableByWindowBackground on control window
        // It's a child window and will move with the main window when main is dragged

        // Create control bar
        controlBar = ControlBar(frame: controlFrame)
        controlBar.videoState = videoState

        // Wrap in a view controller
        let viewController = NSViewController()
        viewController.view = NSView(frame: controlFrame)
        viewController.view.wantsLayer = true
        viewController.view.layer?.backgroundColor = .clear
        viewController.view.addSubview(controlBar)

        controlBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controlBar.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            controlBar.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            controlBar.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ])

        window.contentViewController = viewController
        controlWindow = window
        mainWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)

        // Ensure main window stays key for keyboard events
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func loadSavedWindowFrame(defaultFrame: NSRect, screenFrame: NSRect) -> NSRect {
        guard let savedString = UserDefaults.standard.string(forKey: windowFrameDefaultsKey) else {
            return defaultFrame
        }

        let savedFrame = NSRectFromString(savedString)
        if savedFrame.width <= 0 || savedFrame.height <= 0 {
            return defaultFrame
        }

        return sanitizeWindowFrame(savedFrame, screenFrame: screenFrame)
    }

    private func sanitizeWindowFrame(_ frame: NSRect, screenFrame: NSRect) -> NSRect {
        var adjusted = frame

        if adjusted.width > screenFrame.width {
            adjusted.size.width = screenFrame.width
        }
        if adjusted.height > screenFrame.height {
            adjusted.size.height = screenFrame.height
        }

        if adjusted.minX < screenFrame.minX {
            adjusted.origin.x = screenFrame.minX
        }
        if adjusted.maxX > screenFrame.maxX {
            adjusted.origin.x = screenFrame.maxX - adjusted.width
        }
        if adjusted.minY < screenFrame.minY {
            adjusted.origin.y = screenFrame.minY
        }
        if adjusted.maxY > screenFrame.maxY {
            adjusted.origin.y = screenFrame.maxY - adjusted.height
        }

        return adjusted
    }

    // MARK: - State Observation

    private func observeState() {
        // Lock mode
        videoState.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked in
                guard let window = self?.mainWindow else { return }
                if isLocked {
                    window.styleMask.remove(.resizable)
                    window.ignoresMouseEvents = true
                } else {
                    window.styleMask.insert(.resizable)
                    window.ignoresMouseEvents = false
                }
            }
            .store(in: &cancellables)

        // Always on top
        videoState.$isAlwaysOnTop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnTop in
                guard let self = self else { return }
                let level: NSWindow.Level = isOnTop ? .floating : .normal
                self.mainWindow?.level = level
                self.controlWindow?.level = level
                self.shortcutsWindow?.level = level
            }
            .store(in: &cancellables)

        // Help modal
        videoState.$showHelp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showHelp in
                guard let self = self else { return }
                if showHelp {
                    self.showHelpWindow()
                } else {
                    self.hideHelpWindow()
                }
            }
            .store(in: &cancellables)

        // Filter panel
        videoState.$showFilterPanel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showPanel in
                guard let self = self else { return }
                if showPanel {
                    self.showFilterPanelWindow()
                } else {
                    self.hideFilterPanelWindow()
                }
            }
            .store(in: &cancellables)

        // Open video notification
        NotificationCenter.default.publisher(for: .openVideo)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.openVideoFile()
            }
            .store(in: &cancellables)
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        requestAccessibilityPermissionIfNeeded()

        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKey(event)
        }

        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleGlobalKey(event) == true {
                return nil
            }
            if self?.handleLocalKey(event) == true {
                return nil
            }
            return event
        }
    }

    private func requestAccessibilityPermissionIfNeeded() {
        // Already have permission - no need to prompt
        if AXIsProcessTrusted() {
            return
        }

        // Skip for UI tests
        if ProcessInfo.processInfo.environment["UITEST_MODE"] != nil {
            return
        }

        // Show the system accessibility prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    private func handleGlobalKey(_ event: NSEvent) -> Bool {
        let shortcuts = videoState.shortcutSettings

        // Toggle lock (global)
        if shortcuts.matches(event: event, action: .globalToggleLock) {
            videoState.isLocked.toggle()
            return true
        }

        // Step frame forward (global)
        if shortcuts.matches(event: event, action: .frameStepForward) {
            videoState.requestFrameStep(direction: .forward, amount: 1)
            return true
        }
        if shortcuts.matchesWithMultiplier(event: event, action: .frameStepForward) {
            videoState.requestFrameStep(direction: .forward, amount: 10)
            return true
        }

        // Step frame backward (global)
        if shortcuts.matches(event: event, action: .frameStepBackward) {
            videoState.requestFrameStep(direction: .backward, amount: 1)
            return true
        }
        if shortcuts.matchesWithMultiplier(event: event, action: .frameStepBackward) {
            videoState.requestFrameStep(direction: .backward, amount: 10)
            return true
        }

        return false
    }

    /// Handle app-local keyboard shortcuts that should work from any window
    @discardableResult
    private func handleLocalKey(_ event: NSEvent) -> Bool {
        let shortcuts = videoState.shortcutSettings
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandOnly = flags == [.command]

        // Cmd+A in text fields - select all
        if commandOnly && event.keyCode == KeyCode.a,
           let textView = activeFieldEditor() {
            textView.selectAll(nil)
            return true
        }

        // Enter/Esc in text fields - defocus and return focus to previous app
        if event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.escape,
           let textView = activeFieldEditor() {
            textView.window?.makeFirstResponder(nil)
            NSApp.hide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.unhide(nil)
            }
            return true
        }

        // Don't handle other shortcuts if a text field is first responder
        for window in NSApp.windows {
            if let firstResponder = window.firstResponder, firstResponder is NSTextView {
                return false
            }
        }
        if let keyWindow = NSApp.keyWindow,
           let firstResponder = keyWindow.firstResponder,
           firstResponder is NSTextField {
            return false
        }

        // Frame step (also works locally)
        if shortcuts.matches(event: event, action: .frameStepForward) {
            videoState.requestFrameStep(direction: .forward, amount: 1)
            return true
        }
        if shortcuts.matchesWithMultiplier(event: event, action: .frameStepForward) {
            videoState.requestFrameStep(direction: .forward, amount: 10)
            return true
        }
        if shortcuts.matches(event: event, action: .frameStepBackward) {
            videoState.requestFrameStep(direction: .backward, amount: 1)
            return true
        }
        if shortcuts.matchesWithMultiplier(event: event, action: .frameStepBackward) {
            videoState.requestFrameStep(direction: .backward, amount: 10)
            return true
        }

        // Play/Pause
        if shortcuts.matches(event: event, action: .playPause) && videoState.isVideoLoaded {
            videoState.isPlaying.toggle()
            return true
        }

        // Toggle lock (local)
        if shortcuts.matches(event: event, action: .toggleLock) {
            videoState.isLocked.toggle()
            return true
        }

        // Toggle lock (global) - also works locally
        if shortcuts.matches(event: event, action: .globalToggleLock) {
            videoState.isLocked.toggle()
            return true
        }

        // Show help
        if shortcuts.matches(event: event, action: .showHelp) {
            videoState.showHelp.toggle()
            return true
        }

        // Close modal (Esc) - but not while recording a shortcut
        if shortcuts.matches(event: event, action: .closeModal) && !videoState.isRecordingShortcut {
            if videoState.showHelp {
                videoState.showHelp = false
                return true
            }
            if videoState.showFilterPanel {
                videoState.showFilterPanel = false
                return true
            }
            return false
        }

        // Reset zoom
        if shortcuts.matches(event: event, action: .resetZoom) && videoState.isVideoLoaded && !videoState.isLocked {
            videoState.zoomScale = 1.0
            return true
        }

        // Reset view
        if shortcuts.matches(event: event, action: .resetView) && !videoState.isLocked {
            videoState.resetView()
            return true
        }

        // Toggle filter panel
        if shortcuts.matches(event: event, action: .toggleFilterPanel) && videoState.isVideoLoaded {
            videoState.showFilterPanel.toggle()
            return true
        }

        // Pan shortcuts (with multiplier for 10px)
        if videoState.isVideoLoaded && !videoState.isLocked {
            if shortcuts.matches(event: event, action: .panLeft) {
                videoState.panOffset.width -= 1.0
                return true
            }
            if shortcuts.matchesWithMultiplier(event: event, action: .panLeft) {
                videoState.panOffset.width -= 10.0
                return true
            }
            if shortcuts.matches(event: event, action: .panRight) {
                videoState.panOffset.width += 1.0
                return true
            }
            if shortcuts.matchesWithMultiplier(event: event, action: .panRight) {
                videoState.panOffset.width += 10.0
                return true
            }
            if shortcuts.matches(event: event, action: .panUp) {
                videoState.panOffset.height += 1.0
                return true
            }
            if shortcuts.matchesWithMultiplier(event: event, action: .panUp) {
                videoState.panOffset.height += 10.0
                return true
            }
            if shortcuts.matches(event: event, action: .panDown) {
                videoState.panOffset.height -= 1.0
                return true
            }
            if shortcuts.matchesWithMultiplier(event: event, action: .panDown) {
                videoState.panOffset.height -= 10.0
                return true
            }
        }

        // ? (Shift+/) - Toggle help (legacy, keep for convenience)
        if event.keyCode == KeyCode.questionMark && flags.contains(.shift) {
            videoState.showHelp.toggle()
            return true
        }

        return false
    }

    private func activeFieldEditor() -> NSTextView? {
        for window in NSApp.windows {
            if let textView = window.firstResponder as? NSTextView {
                return textView
            }
            if let textField = window.firstResponder as? NSTextField,
               let editor = window.fieldEditor(false, for: textField) as? NSTextView {
                return editor
            }
        }
        return nil
    }

    // MARK: - Window Frame Updates

    private func observeWindowFrameChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowFrameDidChange),
            name: NSWindow.didMoveNotification,
            object: mainWindow
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowFrameDidChange),
            name: NSWindow.didResizeNotification,
            object: mainWindow
        )
    }

    @objc private func mainWindowFrameDidChange(_ notification: Notification) {
        updateControlWindowFrame()
        updateHelpWindowFrame()
        updateFilterPanelWindowFrame()
        saveWindowFrame()
    }

    private func updateControlWindowFrame() {
        guard let mainWindow = mainWindow, let controlWindow = controlWindow else { return }
        let mainFrame = mainWindow.frame
        // Position toolbar BELOW the main window (flush against bottom edge)
        let controlFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY - controlWindowHeight,
            width: mainFrame.width,
            height: controlWindowHeight
        )
        controlWindow.setFrame(controlFrame, display: true)
    }

    private func saveWindowFrame() {
        guard let mainWindow = mainWindow else { return }
        let frameString = NSStringFromRect(mainWindow.frame)
        UserDefaults.standard.set(frameString, forKey: windowFrameDefaultsKey)
    }

    // MARK: - Help Window

    private func showHelpWindow() {
        if shortcutsWindow == nil {
            let mainFrame = mainWindow.frame
            let size = NSSize(width: 360, height: 500)
            let origin = NSPoint(
                x: mainFrame.midX - size.width / 2,
                y: mainFrame.midY - size.height / 2
            )

            let panel = TransparentWindow(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = mainWindow.level
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true

            let helpView = HelpView(videoState: videoState)
            let viewController = NSViewController()
            viewController.view = helpView
            panel.contentViewController = viewController

            // Set accessibility on both window and view for XCUITest discovery
            panel.setAccessibilityIdentifier("window-help")
            helpView.setAccessibilityIdentifier("modal-help")

            shortcutsWindow = panel
            mainWindow.addChildWindow(panel, ordered: .above)
        }

        shortcutsWindow?.orderFront(nil)
    }

    private func hideHelpWindow() {
        shortcutsWindow?.orderOut(nil)
    }

    private func updateHelpWindowFrame() {
        guard let shortcutsWindow = shortcutsWindow else { return }
        let mainFrame = mainWindow.frame
        let size = shortcutsWindow.frame.size
        let origin = NSPoint(
            x: mainFrame.midX - size.width / 2,
            y: mainFrame.midY - size.height / 2
        )
        shortcutsWindow.setFrameOrigin(origin)
    }

    // MARK: - Filter Panel Window

    private func showFilterPanelWindow() {
        if filterPanelWindow == nil {
            let mainFrame = mainWindow.frame
            let size = NSSize(width: 320, height: 500)
            // Position to the right of main window
            let origin = NSPoint(
                x: mainFrame.maxX + 10,
                y: mainFrame.midY - size.height / 2
            )

            let panel = TransparentWindow(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = mainWindow.level
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true

            let filterPanelView = FilterPanelView(frame: NSRect(origin: .zero, size: size))
            filterPanelView.videoState = videoState

            let viewController = NSViewController()
            viewController.view = filterPanelView
            panel.contentViewController = viewController

            panel.setAccessibilityIdentifier("window-filter-panel")
            filterPanelView.setAccessibilityIdentifier("panel-filter-settings")

            filterPanelWindow = panel
            mainWindow.addChildWindow(panel, ordered: .above)
        }

        filterPanelWindow?.orderFront(nil)
    }

    private func hideFilterPanelWindow() {
        filterPanelWindow?.orderOut(nil)
    }

    private func updateFilterPanelWindowFrame() {
        guard let filterPanelWindow = filterPanelWindow else { return }
        let mainFrame = mainWindow.frame
        let size = filterPanelWindow.frame.size
        let origin = NSPoint(
            x: mainFrame.maxX + 10,
            y: mainFrame.midY - size.height / 2
        )
        filterPanelWindow.setFrameOrigin(origin)
    }

    // MARK: - File Operations

    private func openVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFormats.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a video file"

        // Show as sheet attached to main window so it appears above the floating window
        if let window = mainWindow {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.videoState.isVideoLoaded = false
                self?.videoState.videoURL = url
            }
        } else {
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.videoState.isVideoLoaded = false
                self?.videoState.videoURL = url
            }
        }
    }

    /// Show an error alert as a sheet on the main window
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window = mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Menu Actions (IBActions for storyboard)

    @IBAction func openVideo(_ sender: Any?) {
        openVideoFile()
    }

    @IBAction func resetZoom(_ sender: Any?) {
        videoState.zoomScale = 1.0
    }

    @IBAction func resetPosition(_ sender: Any?) {
        videoState.resetView()
    }

    @IBAction func toggleLock(_ sender: Any?) {
        videoState.isLocked.toggle()
    }

    @IBAction func toggleAlwaysOnTop(_ sender: Any?) {
        videoState.isAlwaysOnTop.toggle()
    }

    @IBAction func togglePlayPause(_ sender: Any?) {
        videoState.isPlaying.toggle()
    }

    @IBAction func stepForward(_ sender: Any?) {
        videoState.requestFrameStep(direction: .forward, amount: 1)
    }

    @IBAction func stepBackward(_ sender: Any?) {
        videoState.requestFrameStep(direction: .backward, amount: 1)
    }

    @IBAction func showKeyboardShortcuts(_ sender: Any?) {
        videoState.showHelp = true
    }

    @IBAction func openReframerHelp(_ sender: Any?) {
        // Show documentation in a floating window above Reframer
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let helpURL = resourceURL
            .appendingPathComponent("Reframer.help")
            .appendingPathComponent("Contents/Resources/en.lproj/index.html")

        // Create or reuse documentation window
        if documentationWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Reframer Documentation"
            window.level = .floating + 1  // Above Reframer's floating level
            window.isReleasedWhenClosed = false

            let webView = WKWebView(frame: window.contentView!.bounds)
            webView.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(webView)

            documentationWindow = window
            documentationWebView = webView
        }

        documentationWebView?.loadFileURL(helpURL, allowingReadAccessTo: resourceURL)
        documentationWindow?.center()
        documentationWindow?.makeKeyAndOrderFront(nil)
    }

    @IBAction func selectFilter(_ sender: NSMenuItem) {
        guard let filter = sender.representedObject as? VideoFilter else { return }
        // Single selection - same as toolbar behavior
        videoState.setQuickFilter(filter)
    }

    @IBAction func clearQuickFilter(_ sender: Any?) {
        videoState.setQuickFilter(nil)
    }

    @IBAction func toggleMinimize(_ sender: Any?) {
        // Toggle minimize - restore if minimized, minimize if not
        if mainWindow.isMiniaturized {
            mainWindow.deminiaturize(sender)
        } else {
            mainWindow.miniaturize(sender)
        }
    }

    @IBAction func showFilterSettings(_ sender: Any?) {
        videoState.showFilterPanel = true
    }

    @IBAction func resetFilterSettings(_ sender: Any?) {
        videoState.resetFilterSettings()
    }

    // MARK: - Installation

    private func ensureInstalledInApplications() {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard !bundleURL.path.hasPrefix(applicationsURL.path) else { return }

        let alert = NSAlert()
        alert.messageText = "Move to Applications folder?"
        alert.informativeText = "Reframer should be installed in /Applications."
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")

        // Show as sheet if main window is ready, otherwise use modal
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performMoveToApplications(from: bundleURL, to: applicationsURL)
        }

        if let window = mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    private func performMoveToApplications(from bundleURL: URL, to applicationsURL: URL) {
        let destinationURL = applicationsURL.appendingPathComponent(bundleURL.lastPathComponent)
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            // Move instead of copy to avoid duplicate app bundles
            try fileManager.moveItem(at: bundleURL, to: destinationURL)

            NSWorkspace.shared.openApplication(at: destinationURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                NSApp.terminate(nil)
            }
        } catch {
            // If move fails (e.g., cross-volume), try copy + delete original
            do {
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
                try? fileManager.removeItem(at: bundleURL) // Best effort delete original
                NSWorkspace.shared.openApplication(at: destinationURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    NSApp.terminate(nil)
                }
            } catch {
                showErrorAlert(title: "Could not move app",
                               message: "Please drag Reframer into /Applications manually.\n\n\(error.localizedDescription)")
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Only handle the Filter menu
        guard menu.title == "Filter" else { return }

        // Remove existing filter items and "None" item
        let itemsToRemove = menu.items.filter { item in
            item.representedObject is VideoFilter || item.title == "None"
        }
        itemsToRemove.forEach { menu.removeItem($0) }

        // Remove placeholder if present
        if let placeholder = menu.items.first(where: { $0.title == "Placeholder" }) {
            menu.removeItem(placeholder)
        }

        // Insert "None" option at the beginning
        let noneItem = NSMenuItem()
        noneItem.title = "None"
        noneItem.image = NSImage(systemSymbolName: "circle.slash", accessibilityDescription: "None")
        noneItem.target = self
        noneItem.action = #selector(clearQuickFilter(_:))
        noneItem.state = (videoState.quickFilter == nil) ? .on : .off
        menu.insertItem(noneItem, at: 0)

        // Insert simple filters only (single selection like toolbar)
        for (index, filter) in VideoFilter.simpleFilters.enumerated() {
            let item = NSMenuItem()
            item.title = filter.rawValue
            item.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: filter.rawValue)
            item.target = self
            item.action = #selector(selectFilter(_:))
            item.representedObject = filter
            // Radio-style: checkmark only on current quickFilter
            item.state = (videoState.quickFilter == filter) ? .on : .off
            menu.insertItem(item, at: index + 1)  // +1 for "None" item
        }
    }
}
