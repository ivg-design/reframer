import Cocoa
import Combine

// Custom window that can become key
class TransparentWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
    private var helpWindow: TransparentWindow?
    private var filterPanelWindow: TransparentWindow?
    private var youtubeProgressAlert: NSAlert?
    private var youtubeResolveToken = UUID()

    let videoState = VideoState()
    private var cancellables = Set<AnyCancellable>()
    private let controlWindowHeight: CGFloat = 40

    private var mainViewController: MainViewController!
    private var controlBar: ControlBar!

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        createMainWindow()
        createControlWindow()
        observeWindowFrameChanges()
        setupGlobalShortcuts()
        observeState()

        // Skip move-to-Applications prompt during UI testing
        if ProcessInfo.processInfo.environment["UITEST_MODE"] == nil {
            ensureInstalledInApplications()
        }

        // Auto-load test video if specified (for UI testing)
        if let testVideoPath = ProcessInfo.processInfo.environment["TEST_VIDEO_PATH"] {
            let url = URL(fileURLWithPath: testVideoPath)
                if FileManager.default.fileExists(atPath: testVideoPath) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.videoState.videoAudioURL = nil
                        self?.videoState.videoHeaders = nil
                        self?.videoState.videoTitle = nil
                        self?.videoState.playbackEngine = .auto
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
                self?.videoState.videoAudioURL = nil
                self?.videoState.videoHeaders = nil
                self?.videoState.videoTitle = nil
                self?.videoState.playbackEngine = .auto
                self?.videoState.isVideoLoaded = false
                self?.videoState.videoURL = url
            }
        } else {
            // Show error for unsupported formats
            let alert = NSAlert()
            alert.messageText = "Unsupported Format"
            alert.informativeText = "The file '\(url.lastPathComponent)' is not a supported video format.\n\nSupported formats: \(VideoFormats.displayString)"
            alert.alertStyle = .warning
            alert.runModal()
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
        appMenu.addItem(withTitle: "Preferences...", action: #selector(showPreferences(_:)), keyEquivalent: ",")
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

        // Filter menu
        let filterMenuItem = NSMenuItem()
        mainMenu.addItem(filterMenuItem)
        let filterMenu = NSMenu(title: "Filter")
        filterMenuItem.submenu = filterMenu
        filterMenu.delegate = self

        // Filter items will be populated dynamically via menu delegate
        filterMenu.addItem(withTitle: "Placeholder", action: nil, keyEquivalent: "")
        filterMenu.addItem(.separator())
        filterMenu.addItem(withTitle: "Clear All Filters", action: #selector(clearAllFilters(_:)), keyEquivalent: "")
        filterMenu.addItem(.separator())
        filterMenu.addItem(withTitle: "Filter Settings...", action: #selector(showFilterSettings(_:)), keyEquivalent: "")
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
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // Help menu - put documentation first since macOS may intercept first item
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "Reframer Documentation", action: #selector(openReframerHelp(_:)), keyEquivalent: "?")
        helpMenu.addItem(.separator())
        helpMenu.addItem(withTitle: "Keyboard Shortcuts", action: #selector(showHelp(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Window Creation

    private func createMainWindow() {
        // Get screen frame for proper centering
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Main window is just the video canvas - toolbar will be BELOW it
        let windowSize = NSSize(width: 800, height: 560)
        let origin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2 + controlWindowHeight / 2
        )
        let windowFrame = NSRect(origin: origin, size: windowSize)

        let window = TransparentWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .resizable],
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
                self.helpWindow?.level = level
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

        // Open YouTube notification
        NotificationCenter.default.publisher(for: .openYouTube)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.openYouTubePrompt()
            }
            .store(in: &cancellables)
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
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

    @discardableResult
    private func handleGlobalKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasShift = flags.contains(.shift)

        // Cmd+Shift+L - Toggle lock (global)
        if hasCommand && hasShift && event.keyCode == 37 {
            videoState.isLocked.toggle()
            return true
        }

        // Cmd+PageUp - Step frame forward (global)
        if hasCommand && event.keyCode == 116 {
            NotificationCenter.default.post(name: .frameStepForward, object: hasShift ? 10 : 1)
            return true
        }

        // Cmd+PageDown - Step frame backward (global)
        if hasCommand && event.keyCode == 121 {
            NotificationCenter.default.post(name: .frameStepBackward, object: hasShift ? 10 : 1)
            return true
        }

        return false
    }

    /// Handle app-local keyboard shortcuts that should work from any window
    @discardableResult
    private func handleLocalKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let noModifiers = flags.isEmpty

        // Don't handle if a text field is first responder (check all windows)
        // Check ALL windows, not just key window, since control bar is in separate window
        for window in NSApp.windows {
            if let firstResponder = window.firstResponder,
               firstResponder is NSTextView {
                return false
            }
        }

        // Also check specific field editor state
        if let keyWindow = NSApp.keyWindow,
           let firstResponder = keyWindow.firstResponder,
           firstResponder is NSTextField {
            return false
        }

        switch event.keyCode {
        // Space - Play/Pause
        case 49 where noModifiers && videoState.isVideoLoaded:
            videoState.isPlaying.toggle()
            return true

        // L - Toggle lock
        case 37 where noModifiers:
            videoState.isLocked.toggle()
            return true

        // H - Toggle help
        case 4 where noModifiers:
            videoState.showHelp.toggle()
            return true

        // 0 - Reset zoom to 100%
        case 29 where noModifiers && videoState.isVideoLoaded && !videoState.isLocked:
            videoState.zoomScale = 1.0
            return true

        // R - Reset view
        case 15 where noModifiers && !videoState.isLocked:
            videoState.resetView()
            return true

        // ? (Shift+/) - Toggle help
        case 44 where flags.contains(.shift):
            videoState.showHelp.toggle()
            return true

        // Escape - Close help or filter panel
        case 53:
            if videoState.showHelp {
                videoState.showHelp = false
                return true
            }
            if videoState.showFilterPanel {
                videoState.showFilterPanel = false
                return true
            }
            return false

        // F - Toggle filter panel
        case 3 where videoState.isVideoLoaded && noModifiers:
            videoState.showFilterPanel.toggle()
            return true

        // Arrow keys for pan (when unlocked and video loaded)
        case 123 where videoState.isVideoLoaded && !videoState.isLocked: // Left
            let amount = (flags.contains(.command) && flags.contains(.shift)) ? 100.0 : (flags.contains(.shift) ? 10.0 : 1.0)
            videoState.panOffset.width -= amount
            return true

        case 124 where videoState.isVideoLoaded && !videoState.isLocked: // Right
            let amount = (flags.contains(.command) && flags.contains(.shift)) ? 100.0 : (flags.contains(.shift) ? 10.0 : 1.0)
            videoState.panOffset.width += amount
            return true

        case 126 where videoState.isVideoLoaded && !videoState.isLocked: // Up
            let amount = (flags.contains(.command) && flags.contains(.shift)) ? 100.0 : (flags.contains(.shift) ? 10.0 : 1.0)
            videoState.panOffset.height += amount
            return true

        case 125 where videoState.isVideoLoaded && !videoState.isLocked: // Down
            let amount = (flags.contains(.command) && flags.contains(.shift)) ? 100.0 : (flags.contains(.shift) ? 10.0 : 1.0)
            videoState.panOffset.height -= amount
            return true

        default:
            return false
        }
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

    // MARK: - Help Window

    private func showHelpWindow() {
        if helpWindow == nil {
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

            helpWindow = panel
            mainWindow.addChildWindow(panel, ordered: .above)
        }

        helpWindow?.orderFront(nil)
    }

    private func hideHelpWindow() {
        helpWindow?.orderOut(nil)
    }

    private func updateHelpWindowFrame() {
        guard let helpWindow = helpWindow else { return }
        let mainFrame = mainWindow.frame
        let size = helpWindow.frame.size
        let origin = NSPoint(
            x: mainFrame.midX - size.width / 2,
            y: mainFrame.midY - size.height / 2
        )
        helpWindow.setFrameOrigin(origin)
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

        if panel.runModal() == .OK, let url = panel.url {
            videoState.videoAudioURL = nil
            videoState.videoHeaders = nil
            videoState.videoTitle = nil
            videoState.playbackEngine = .auto
            videoState.isVideoLoaded = false
            videoState.videoURL = url
        }
    }

    private func openYouTubePrompt() {
        let alert = NSAlert()
        alert.messageText = "Open YouTube Video"
        alert.informativeText = "Paste a YouTube link to start playback."

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        inputField.placeholderString = "https://www.youtube.com/watch?v=..."
        inputField.setAccessibilityIdentifier("youtube-url-input")
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            inputField.stringValue = clipboard
        }
        alert.accessoryView = inputField
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let trimmed = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed) else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Invalid URL"
                errorAlert.informativeText = "Please enter a valid YouTube URL."
                errorAlert.runModal()
                return
            }
            resolveYouTubeURL(url)
        }
    }

    private func resolveYouTubeURL(_ url: URL) {
        let token = UUID()
        youtubeResolveToken = token

        showYouTubeProgress()
        YouTubeResolver.shared.resolve(url: url) { [weak self] result in
            guard let self = self, self.youtubeResolveToken == token else { return }
            self.hideYouTubeProgress()

            switch result {
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "YouTube Playback Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            case .success(let selection):
                var candidate = selection.primary
                var engine: VideoState.PlaybackEngine = .avFoundation

                if !candidate.isAVFoundationCompatible {
                    if VLCKitManager.shared.isReady {
                        engine = .vlc
                    } else if let fallback = selection.fallbackCombined,
                              fallback.isAVFoundationCompatible {
                        candidate = fallback
                        engine = .avFoundation
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "YouTube Format Not Supported"
                        alert.informativeText = "The highest-quality stream requires VLC. Install and enable VLCKit to play this video."
                        alert.alertStyle = .warning
                        alert.runModal()
                        return
                    }
                }

                self.videoState.videoAudioURL = candidate.audioURL
                self.videoState.videoHeaders = selection.headers
                self.videoState.videoTitle = selection.title
                self.videoState.playbackEngine = engine
                self.videoState.isVideoLoaded = false
                self.videoState.videoURL = candidate.videoURL
                self.videoState.isPlaying = true
            }
        }
    }

    private func showYouTubeProgress() {
        let alert = NSAlert()
        alert.messageText = "Resolving YouTube Stream"
        alert.informativeText = "Fetching stream information…"
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: "Please wait")
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        alert.accessoryView = stack

        youtubeProgressAlert = alert

        if let window = mainWindow {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.youtubeResolveToken = UUID()
                    self?.hideYouTubeProgress()
                }
            }
        } else {
            alert.runModal()
        }
    }

    private func hideYouTubeProgress() {
        guard let alert = youtubeProgressAlert else { return }
        if let window = mainWindow, let sheet = window.attachedSheet, sheet == alert.window {
            window.endSheet(sheet)
        } else {
            alert.window.orderOut(nil)
        }
        youtubeProgressAlert = nil
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
        NotificationCenter.default.post(name: .frameStepForward, object: 1)
    }

    @IBAction func stepBackward(_ sender: Any?) {
        NotificationCenter.default.post(name: .frameStepBackward, object: 1)
    }

    @IBAction func showHelp(_ sender: Any?) {
        videoState.showHelp = true
    }

    @IBAction func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow()
    }

    @IBAction func openReframerHelp(_ sender: Any?) {
        // Open the Reframer help book
        let helpBookName = Bundle.main.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String ?? "com.reframer.help"
        NSHelpManager.shared.openHelpAnchor("index", inBook: helpBookName)
    }

    @IBAction func toggleFilter(_ sender: NSMenuItem) {
        guard let filter = sender.representedObject as? VideoFilter else { return }
        videoState.toggleAdvancedFilter(filter)
    }

    @IBAction func clearAllFilters(_ sender: Any?) {
        videoState.clearAdvancedFilters()
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
        alert.informativeText = "Video Overlay should be installed in /Applications."
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let destinationURL = applicationsURL.appendingPathComponent(bundleURL.lastPathComponent)
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: bundleURL, to: destinationURL)

            NSWorkspace.shared.openApplication(at: destinationURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                NSApp.terminate(nil)
            }
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.messageText = "Could not move app"
            errorAlert.informativeText = "Please drag Video Overlay into /Applications manually."
            errorAlert.runModal()
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Only handle the Filter menu
        guard menu.title == "Filter" else { return }

        // Remove existing filter items (keep separators and other items)
        let itemsToRemove = menu.items.filter { item in
            item.representedObject is VideoFilter
        }
        itemsToRemove.forEach { menu.removeItem($0) }

        // Remove placeholder if present
        if let placeholder = menu.items.first(where: { $0.title == "Placeholder" }) {
            menu.removeItem(placeholder)
        }

        // Insert filter items at the beginning
        for (index, filter) in VideoFilter.allCases.enumerated() {
            let item = NSMenuItem()
            item.title = filter.rawValue
            item.image = NSImage(systemSymbolName: filter.iconName, accessibilityDescription: filter.rawValue)
            item.target = self
            item.action = #selector(toggleFilter(_:))
            item.representedObject = filter
            item.state = videoState.isAdvancedFilterActive(filter) ? .on : .off
            menu.insertItem(item, at: index)
        }
    }
}
