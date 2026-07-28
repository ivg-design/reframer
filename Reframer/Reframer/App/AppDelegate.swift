import Cocoa
import Combine
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

private final class ReframerCommandBox: NSObject {
    let command: ReframerCommand

    init(_ command: ReframerCommand) {
        self.command = command
    }
}

enum AuxiliaryPanelKind: CaseIterable, Hashable {
    case shortcutSettings
    case filters
    case documentation
}

enum AuxiliaryPanelRouting {
    static func target(
        keyPanel: AuxiliaryPanelKind?,
        orderedVisiblePanels: [AuxiliaryPanelKind],
        visiblePanels: Set<AuxiliaryPanelKind>
    ) -> AuxiliaryPanelKind? {
        if let keyPanel, visiblePanels.contains(keyPanel) {
            return keyPanel
        }
        if let ordered = orderedVisiblePanels.first(where: visiblePanels.contains) {
            return ordered
        }
        return AuxiliaryPanelKind.allCases.first(where: visiblePanels.contains)
    }
}

enum FocusedShortcutEventDecision: Equatable {
    case passThrough
    case deliverToFocusedResponder
    case consumeWithoutDispatch
    case dispatch(ShortcutMatch)
}

enum FocusedShortcutEventRouting {
    static func decision(
        resolution: ShortcutEventResolution,
        focusedResponderOwnsStroke: Bool
    ) -> FocusedShortcutEventDecision {
        switch resolution {
        case .unmatched:
            return .passThrough
        case .consumeWithoutDispatch:
            return focusedResponderOwnsStroke
                ? .deliverToFocusedResponder
                : .consumeWithoutDispatch
        case .dispatch(let match):
            return focusedResponderOwnsStroke
                ? .deliverToFocusedResponder
                : .dispatch(match)
        }
    }
}

enum ShortcutWindowRouting {
    static func shouldBypassApplicationShortcuts(
        isSystemSavePanel: Bool,
        hasSheetParent: Bool
    ) -> Bool {
        isSystemSavePanel || hasSheetParent
    }

    static func shouldBypassApplicationShortcuts(in window: NSWindow?) -> Bool {
        guard let window else { return true }
        return shouldBypassApplicationShortcuts(
            isSystemSavePanel: window is NSSavePanel,
            hasSheetParent: window.sheetParent != nil
        )
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private final class FocusSnapshot {
        weak var window: NSWindow?
        weak var responder: NSResponder?

        init(window: NSWindow?, responder: NSResponder?) {
            self.window = window
            self.responder = responder
        }
    }

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

    private var globalHotKeyRegistrar: GlobalHotKeyRegistrar?
    private var localShortcutMonitor: Any?
    var mainWindow: TransparentWindow!
    private var controlWindow: TransparentWindow!
    private var shortcutsWindow: TransparentWindow?  // Keyboard shortcuts panel (H key)
    private weak var shortcutsView: HelpView?
    private var documentationWindow: NSWindow?        // Documentation browser (Help menu)
    private var documentationWebView: WKWebView?
    private var filterPanelWindow: TransparentWindow?
    private weak var filterPanelView: FilterPanelView?
    private var alwaysOnTopMenuItem: NSMenuItem?

    let videoState = VideoState()
    private var cancellables = Set<AnyCancellable>()
    /// Kept in sync with ControlBar.xib so the child window and its content
    /// have one layout height and never create conflicting constraints.
    private let controlWindowHeight: CGFloat = 48
    private let mainWindowMinimumSize = NSSize(
        width: ControlBar.minimumUsableWidth,
        height: 360
    )
    private let windowFrameDefaultsKey = "VideoOverlay.mainWindowFrame"
    private var windowReclampWorkItem: DispatchWorkItem?
    private var isRepositioningWindows = false
    private var helpFocusSnapshot: FocusSnapshot?
    private var filterFocusSnapshot: FocusSnapshot?
    private var documentationFocusSnapshot: FocusSnapshot?

    private var mainViewController: MainViewController!
    private var controlBar: ControlBar!
    private var shortcutMenuItems: [
        (item: NSMenuItem, action: ShortcutSettings.Action, factor: Int)
    ] = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        createMainWindow()
        createControlWindow()
        observeWindowFrameChanges()
        setupGlobalShortcuts()
        observeState()

        #if DEBUG
        // Development-only convenience hook. The shipping app accepts video
        // URLs only through user-mediated open, drop, or Open With flows.
        if let testVideoPath = ProcessInfo.processInfo.environment["TEST_VIDEO_PATH"] {
            let url = URL(fileURLWithPath: testVideoPath)
            if FileManager.default.fileExists(atPath: testVideoPath) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.videoState.isVideoLoaded = false
                    self?.videoState.videoURL = url
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowReclampWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        globalHotKeyRegistrar?.invalidate()
        globalHotKeyRegistrar = nil
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
        shortcutMenuItems.removeAll()
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About Reframer",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Reframer",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Reframer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(makeCommandMenuItem(
            title: "Open Video…",
            command: .openVideo,
            keyEquivalent: "o",
            modifiers: [.command]
        ))

        // A standard Edit menu keeps native text editing commands intact.
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

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(makeShortcutMenuItem(
            title: "Reset Zoom",
            command: .resetZoom,
            action: .resetZoom
        ))
        viewMenu.addItem(makeShortcutMenuItem(
            title: "Reset View",
            command: .resetView,
            action: .resetView
        ))

        let panItem = NSMenuItem(title: "Pan", action: nil, keyEquivalent: "")
        let panMenu = NSMenu(title: "Pan")
        panItem.submenu = panMenu
        let panActions: [(ShortcutSettings.Action, String, Double, Double)] = [
            (.panLeft, "Left", -1, 0),
            (.panRight, "Right", 1, 0),
            (.panUp, "Up", 0, 1),
            (.panDown, "Down", 0, -1)
        ]
        for (index, action) in panActions.enumerated() {
            if index > 0 { panMenu.addItem(.separator()) }
            for factor in [1, 10, 100] {
                panMenu.addItem(makeShortcutMenuItem(
                    title: "\(action.1) \(factor) pt",
                    command: .pan(
                        x: action.2 * Double(factor),
                        y: action.3 * Double(factor)
                    ),
                    action: action.0,
                    factor: factor
                ))
            }
        }
        viewMenu.addItem(panItem)
        viewMenu.addItem(.separator())

        let lockItem = makeShortcutMenuItem(
            title: "Lock Overlay",
            command: .toggleLock,
            action: .toggleLock
        )
        viewMenu.addItem(lockItem)
        viewMenu.addItem(makeShortcutMenuItem(
            title: "Toggle Lock (Global Shortcut)",
            command: .toggleLock,
            action: .globalToggleLock
        ))
        let alwaysOnTopItem = makeCommandMenuItem(
            title: "Always on Top",
            command: .toggleAlwaysOnTop
        )
        viewMenu.addItem(alwaysOnTopItem)
        alwaysOnTopMenuItem = alwaysOnTopItem

        let filterMenuItem = NSMenuItem()
        mainMenu.addItem(filterMenuItem)
        let filterMenu = NSMenu(title: "Filter")
        filterMenuItem.submenu = filterMenu
        filterMenu.delegate = self
        filterMenu.addItem(withTitle: "Placeholder", action: nil, keyEquivalent: "")
        filterMenu.addItem(.separator())
        filterMenu.addItem(makeShortcutMenuItem(
            title: "Advanced Filters…",
            command: .toggleFilterPanel,
            action: .toggleFilterPanel
        ))
        filterMenu.addItem(.separator())
        filterMenu.addItem(
            withTitle: "Reset Filter Parameters",
            action: #selector(resetFilterSettings(_:)),
            keyEquivalent: ""
        )

        let playbackMenuItem = NSMenuItem()
        mainMenu.addItem(playbackMenuItem)
        let playbackMenu = NSMenu(title: "Playback")
        playbackMenuItem.submenu = playbackMenu
        playbackMenu.addItem(makeShortcutMenuItem(
            title: "Play / Pause",
            command: .togglePlayPause,
            action: .playPause
        ))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(makeShortcutMenuItem(
            title: "Step Forward 1 Frame",
            command: .step(.forward, amount: 1),
            action: .frameStepForward
        ))
        playbackMenu.addItem(makeShortcutMenuItem(
            title: "Step Forward 10 Frames",
            command: .step(.forward, amount: 10),
            action: .frameStepForward,
            factor: 10
        ))
        playbackMenu.addItem(makeShortcutMenuItem(
            title: "Step Backward 1 Frame",
            command: .step(.backward, amount: 1),
            action: .frameStepBackward
        ))
        playbackMenu.addItem(makeShortcutMenuItem(
            title: "Step Backward 10 Frames",
            command: .step(.backward, amount: 10),
            action: .frameStepBackward,
            factor: 10
        ))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(makeCommandMenuItem(
            title: "Minimize",
            command: .toggleMinimize,
            keyEquivalent: "m",
            modifiers: [.command]
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(makeCommandMenuItem(
            title: "Reframer Documentation",
            command: .openDocumentation,
            // Preserve the conventional menu presentation. The local event
            // layer resolves the physical Command-Shift-/ chord before AppKit
            // opens Help-menu search.
            keyEquivalent: "?",
            modifiers: [.command]
        ))
        helpMenu.addItem(makeShortcutMenuItem(
            title: "Shortcut Settings…",
            command: .toggleShortcutSettings,
            action: .showHelp
        ))
        helpMenu.addItem(makeShortcutMenuItem(
            title: "Close Current Panel",
            command: .closeContext,
            action: .closeModal
        ))

        NSApp.mainMenu = mainMenu
        syncShortcutMenuItems()
    }

    private func makeCommandMenuItem(
        title: String,
        command: ReframerCommand,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(performCommandMenuItem(_:)),
            keyEquivalent: keyEquivalent
        )
        item.target = self
        item.representedObject = ReframerCommandBox(command)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func makeShortcutMenuItem(
        title: String,
        command: ReframerCommand,
        action: ShortcutSettings.Action,
        factor: Int = 1
    ) -> NSMenuItem {
        let item = makeCommandMenuItem(title: title, command: command)
        shortcutMenuItems.append((item, action, factor))
        return item
    }

    private func syncShortcutMenuItems() {
        let settings = videoState.shortcutSettings
        for entry in shortcutMenuItems {
            let binding = settings.binding(for: entry.action)
            guard binding.isEnabled,
                  let shortcut = binding.shortcut,
                  let equivalent = shortcut.menuKeyEquivalent else {
                entry.item.keyEquivalent = ""
                entry.item.keyEquivalentModifierMask = []
                continue
            }
            entry.item.keyEquivalent = equivalent
            entry.item.keyEquivalentModifierMask = shortcut.menuModifierMask(factor: entry.factor)
        }
    }

    // MARK: - Window Creation

    private func createMainWindow() {
        let visibleFrames = currentVisibleScreenFrames()
        let screenFrame = NSScreen.main?.visibleFrame
            ?? visibleFrames.first
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Main window is just the video canvas - toolbar will be BELOW it
        let windowSize = NSSize(width: ControlBar.minimumUsableWidth, height: 560)
        let defaultOrigin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2 + controlWindowHeight / 2
        )
        let defaultFrame = NSRect(origin: defaultOrigin, size: windowSize)
        let windowFrame = loadSavedWindowFrame(
            defaultFrame: defaultFrame,
            visibleFrames: visibleFrames.isEmpty ? [screenFrame] : visibleFrames
        )

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
        window.level = desiredWindowLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The dedicated, lock-aware control-bar grip owns window movement.
        // Background dragging would steal primary-button video panning.
        window.isMovableByWindowBackground = false
        window.minSize = mainWindowMinimumSize
        window.title = "Reframer Video Overlay"
        window.setAccessibilityIdentifier("window-main")
        window.setAccessibilityLabel("Reframer Video Overlay")

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
        window.title = "Reframer Controls"
        window.setAccessibilityIdentifier("window-controls")
        window.setAccessibilityLabel("Reframer Controls")
        // NOTE: Do NOT set isMovableByWindowBackground on control window
        // It's a child window and will move with the main window when main is dragged

        // Create control bar
        controlBar = ControlBar(frame: controlFrame)
        controlBar.videoState = videoState
        controlBar.windowToDrag = mainWindow

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

    private func loadSavedWindowFrame(defaultFrame: NSRect, visibleFrames: [NSRect]) -> NSRect {
        let candidateFrame: NSRect
        if let savedString = UserDefaults.standard.string(forKey: windowFrameDefaultsKey) {
            let savedFrame = NSRectFromString(savedString)
            candidateFrame = WindowPlacement.isUsableFrame(savedFrame)
                ? savedFrame
                : defaultFrame
        } else {
            candidateFrame = defaultFrame
        }

        return WindowPlacement.clampMainFrame(
            candidateFrame,
            visibleFrames: visibleFrames,
            toolbarHeight: controlWindowHeight,
            minimumSize: mainWindowMinimumSize
        )
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
                self.applyWindowLevels(isAlwaysOnTop: isOnTop)
                self.alwaysOnTopMenuItem?.state = isOnTop ? .on : .off
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
                _ = self?.dispatch(.openVideo, origin: .menu)
            }
            .store(in: &cancellables)

        videoState.shortcutSettings.$bindings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncShortcutMenuItems()
                self?.registerGlobalHotKeys()
            }
            .store(in: &cancellables)

        videoState.shortcutSettings.$recordingAction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.videoState.isRecordingShortcut = action != nil
                self?.registerGlobalHotKeys()
            }
            .store(in: &cancellables)

        videoState.shortcutSettings.$globalShortcutsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerGlobalHotKeys()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            videoState.$isVideoLoaded,
            videoState.$isLocked,
            videoState.$totalFrames,
            videoState.$frameNavigationPrecision
        )
            .map { isLoaded, isLocked, totalFrames, precision in
                isLoaded
                    && isLocked
                    && totalFrames > 0
                    && precision.supportsFrameNavigation
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerGlobalHotKeys()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .reconfigureGlobalHotKeys)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerGlobalHotKeys()
            }
            .store(in: &cancellables)
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        globalHotKeyRegistrar = GlobalHotKeyRegistrar { [weak self] match in
            guard let self else { return }
            guard RegisteredHotKeyRouting.shouldDeliverCarbonEvent(
                isApplicationActive: NSApp.isActive
            ) else {
                return
            }
            let command = self.videoState.shortcutSettings.command(for: match)
            _ = self.dispatch(command, origin: .globalShortcut)
        }
        registerGlobalHotKeys()

        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            if self?.handleLocalEvent(event) == true {
                return nil
            }
            return event
        }
    }

    private func registerGlobalHotKeys() {
        let settings = videoState.shortcutSettings
        guard let globalHotKeyRegistrar else {
            settings.setGlobalRegistrationStatus(.pending)
            return
        }
        let status = globalHotKeyRegistrar.apply(
            settings: settings,
            includeFrameSteps: videoState.isLocked && videoState.canNavigateFrames,
            suspended: settings.recordingAction != nil
        )
        settings.setGlobalRegistrationStatus(status)
    }

    /// Handles recording first, preserves only the native keys a focused
    /// control actually owns, and dispatches an app shortcut exactly once.
    @discardableResult
    private func handleLocalEvent(_ event: NSEvent) -> Bool {
        // Native sheets and system file panels own their complete keyboard
        // interaction. Reframer shortcuts must not turn Space/arrows into
        // playback or pan commands while the user is choosing a file or
        // responding to an alert.
        guard !ShortcutWindowRouting.shouldBypassApplicationShortcuts(
            in: NSApp.keyWindow
        ) else {
            return false
        }

        let settings = videoState.shortcutSettings

        if settings.recordingAction != nil {
            if event.type == .flagsChanged {
                return true
            }
            return settings.record(stroke: ShortcutKeystroke(event: event)) != .notRecording
        }

        guard event.type == .keyDown else { return false }
        let stroke = ShortcutKeystroke(event: event)

        switch FixedCommandShortcutRouting.eventResolution(stroke: stroke) {
        case .unmatched:
            break
        case .consumeWithoutDispatch:
            return true
        case .dispatch(let command):
            return dispatch(command, origin: .localShortcut)
        }

        let resolution = settings.eventResolution(stroke: stroke, scope: .local)

        let responder = activeFieldEditor() ?? NSApp.keyWindow?.firstResponder
        let decision = FocusedShortcutEventRouting.decision(
            resolution: resolution,
            focusedResponderOwnsStroke: ShortcutControlRouting.focusedResponderOwns(
                stroke: stroke,
                responder: responder
            )
        )
        switch decision {
        case .passThrough:
            return false
        case .deliverToFocusedResponder:
            responder?.keyDown(with: event)
            return true
        case .consumeWithoutDispatch:
            return true
        case .dispatch(let match):
            return dispatch(settings.command(for: match), origin: .localShortcut)
        }
    }

    private func activeFieldEditor() -> NSTextView? {
        guard let window = NSApp.keyWindow else { return nil }
        if let textView = window.firstResponder as? NSTextView {
            return textView
        }
        if let textField = window.firstResponder as? NSTextField,
           let editor = window.fieldEditor(false, for: textField) as? NSTextView {
            return editor
        }
        return nil
    }

    // MARK: - Unified Command Dispatch

    @discardableResult
    private func dispatch(
        _ command: ReframerCommand,
        origin: ReframerCommandOrigin
    ) -> Bool {
        guard isCommandAvailable(command, origin: origin) else { return false }

        switch command {
        case .openVideo:
            openVideoFile()
        case .togglePlayPause:
            videoState.isPlaying.toggle()
        case .step(let direction, let amount):
            videoState.requestFrameStep(direction: direction, amount: amount)
        case .pan(let x, let y):
            videoState.panOffset.width += CGFloat(x)
            videoState.panOffset.height += CGFloat(y)
        case .resetZoom:
            videoState.zoomScale = 1.0
        case .resetView:
            videoState.resetView()
        case .toggleLock:
            videoState.isLocked.toggle()
        case .toggleAlwaysOnTop:
            videoState.isAlwaysOnTop.toggle()
        case .toggleShortcutSettings:
            videoState.showHelp.toggle()
        case .toggleFilterPanel:
            videoState.showFilterPanel.toggle()
        case .closeContext:
            switch currentAuxiliaryPanel() {
            case .shortcutSettings:
                videoState.showHelp = false
            case .filters:
                videoState.showFilterPanel = false
            case .documentation:
                hideDocumentationWindow()
            case nil:
                return false
            }
        case .openDocumentation:
            openDocumentationWindow()
        case .toggleMinimize:
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            } else {
                mainWindow.miniaturize(nil)
            }
        }
        return true
    }

    private func isCommandAvailable(
        _ command: ReframerCommand,
        origin: ReframerCommandOrigin
    ) -> Bool {
        ReframerCommandAvailability.isAvailable(
            command,
            origin: origin,
            context: ReframerCommandAvailabilityContext(
                isVideoLoaded: videoState.isVideoLoaded,
                isLocked: videoState.isLocked,
                canNavigateFrames: videoState.canNavigateFrames,
                isHelpVisible: videoState.showHelp,
                isFilterPanelVisible: videoState.showFilterPanel,
                isDocumentationVisible: documentationWindow?.isVisible == true
            )
        )
    }

    private func currentAuxiliaryPanel() -> AuxiliaryPanelKind? {
        let windows: [(NSWindow?, AuxiliaryPanelKind)] = [
            (shortcutsWindow, .shortcutSettings),
            (filterPanelWindow, .filters),
            (documentationWindow, .documentation)
        ]
        let visiblePanels = Set(windows.compactMap { window, kind in
            window?.isVisible == true ? kind : nil
        })
        let keyPanel = windows.first(where: { $0.0 === NSApp.keyWindow })?.1
        let orderedVisiblePanels = NSApp.orderedWindows.compactMap { orderedWindow in
            windows.first(where: { $0.0 === orderedWindow })?.1
        }
        return AuxiliaryPanelRouting.target(
            keyPanel: keyPanel,
            orderedVisiblePanels: orderedVisiblePanels,
            visiblePanels: visiblePanels
        )
    }

    @objc private func performCommandMenuItem(_ sender: NSMenuItem) {
        guard let command = (sender.representedObject as? ReframerCommandBox)?.command else {
            return
        }
        _ = dispatch(command, origin: .menu)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = (menuItem.representedObject as? ReframerCommandBox)?.command else {
            return true
        }
        switch command {
        case .toggleLock:
            menuItem.state = videoState.isLocked ? .on : .off
        case .toggleAlwaysOnTop:
            menuItem.state = videoState.isAlwaysOnTop ? .on : .off
        case .toggleShortcutSettings:
            menuItem.state = videoState.showHelp ? .on : .off
        case .toggleFilterPanel:
            menuItem.state = videoState.showFilterPanel ? .on : .off
        default:
            break
        }
        return isCommandAvailable(command, origin: .menu)
    }

    // MARK: - Window Frame Updates

    private var desiredWindowLevel: NSWindow.Level {
        videoState.isAlwaysOnTop ? .floating : .normal
    }

    private func applyWindowLevels(isAlwaysOnTop: Bool) {
        let level: NSWindow.Level = isAlwaysOnTop ? .floating : .normal
        mainWindow?.level = level
        controlWindow?.level = level
        shortcutsWindow?.level = level
        filterPanelWindow?.level = level
        documentationWindow?.level = level
    }

    private func currentVisibleScreenFrames() -> [NSRect] {
        NSScreen.screens
            .map(\.visibleFrame)
            .filter(WindowPlacement.isUsableFrame)
    }

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowScreenDidChange),
            name: NSWindow.didChangeScreenNotification,
            object: mainWindow
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func mainWindowFrameDidChange(_ notification: Notification) {
        guard !isRepositioningWindows else { return }
        updateControlWindowFrame()
        updateHelpWindowFrame()
        updateFilterPanelWindowFrame()
        saveWindowFrame()
        scheduleMainWindowReclamp()
    }

    @objc private func mainWindowScreenDidChange(_ notification: Notification) {
        reclampWindowsToVisibleScreens()
    }

    @objc private func screenConfigurationDidChange(_ notification: Notification) {
        reclampWindowsToVisibleScreens()
    }

    private func scheduleMainWindowReclamp() {
        windowReclampWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reclampWindowsToVisibleScreens()
        }
        windowReclampWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func reclampWindowsToVisibleScreens() {
        guard let mainWindow, !isRepositioningWindows else { return }
        let visibleFrames = currentVisibleScreenFrames()
        guard !visibleFrames.isEmpty else { return }

        windowReclampWorkItem?.cancel()
        windowReclampWorkItem = nil
        isRepositioningWindows = true
        defer { isRepositioningWindows = false }

        let mainFrame = WindowPlacement.clampMainFrame(
            mainWindow.frame,
            visibleFrames: visibleFrames,
            toolbarHeight: controlWindowHeight,
            minimumSize: mainWindowMinimumSize
        )
        if mainFrame != mainWindow.frame {
            mainWindow.setFrame(mainFrame, display: true)
        }

        updateControlWindowFrame()
        updateHelpWindowFrame()
        updateFilterPanelWindowFrame()
        updateDocumentationWindowFrame()
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
        guard let mainWindow = mainWindow,
              WindowPlacement.isUsableFrame(mainWindow.frame) else { return }
        let frameString = NSStringFromRect(mainWindow.frame)
        UserDefaults.standard.set(frameString, forKey: windowFrameDefaultsKey)
    }

    private func centeredAuxiliaryFrame(size: NSSize) -> NSRect {
        let mainFrame = mainWindow.frame
        let desiredFrame = NSRect(
            x: mainFrame.midX - size.width / 2,
            y: mainFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let visibleFrames = currentVisibleScreenFrames()
        let anchorScreen = WindowPlacement.bestVisibleFrame(
            for: mainFrame,
            among: visibleFrames
        )
        return WindowPlacement.clampAuxiliaryFrame(
            desiredFrame,
            visibleFrames: visibleFrames,
            preferredScreenFrame: anchorScreen
        )
    }

    private func captureFocus() -> FocusSnapshot {
        let window = NSApp.keyWindow ?? mainWindow
        return FocusSnapshot(window: window, responder: window?.firstResponder)
    }

    private func restoreFocus(from snapshot: FocusSnapshot?) {
        let targetWindow: NSWindow
        if let window = snapshot?.window, window.isVisible, !window.isMiniaturized {
            targetWindow = window
        } else {
            targetWindow = mainWindow
        }

        targetWindow.makeKeyAndOrderFront(nil)
        if let responder = snapshot?.responder,
           targetWindow.makeFirstResponder(responder) {
            return
        }
        _ = targetWindow.makeFirstResponder(mainViewController)
    }

    // MARK: - Help Window

    private func showHelpWindow() {
        if shortcutsWindow?.isVisible != true {
            helpFocusSnapshot = captureFocus()
        }

        if shortcutsWindow == nil {
            let size = NSSize(width: 520, height: 640)
            let frame = centeredAuxiliaryFrame(size: size)

            let panel = TransparentWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = desiredWindowLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.title = "Shortcut Settings"
            panel.setAccessibilityLabel("Shortcut Settings")

            let helpView = HelpView(videoState: videoState)
            let viewController = NSViewController()
            viewController.view = helpView
            panel.contentViewController = viewController

            // Set accessibility on both window and view for XCUITest discovery
            panel.setAccessibilityIdentifier("window-help")
            helpView.setAccessibilityIdentifier("modal-help")

            shortcutsWindow = panel
            shortcutsView = helpView
            mainWindow.addChildWindow(panel, ordered: .above)
        }

        updateHelpWindowFrame()
        shortcutsWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let panel = self.shortcutsWindow,
                  panel.isVisible,
                  let initialResponder = self.shortcutsView?.preferredInitialFirstResponder else {
                return
            }
            _ = panel.makeFirstResponder(initialResponder)
        }
    }

    private func hideHelpWindow() {
        let shouldRestoreFocus = shortcutsWindow?.isKeyWindow == true
        videoState.shortcutSettings.cancelRecording()
        shortcutsWindow?.orderOut(nil)
        let snapshot = helpFocusSnapshot
        helpFocusSnapshot = nil
        if shouldRestoreFocus {
            restoreFocus(from: snapshot)
        }
    }

    private func updateHelpWindowFrame() {
        guard let shortcutsWindow = shortcutsWindow else { return }
        let frame = centeredAuxiliaryFrame(size: shortcutsWindow.frame.size)
        shortcutsWindow.setFrame(frame, display: shortcutsWindow.isVisible)
    }

    // MARK: - Filter Panel Window

    private func showFilterPanelWindow() {
        if filterPanelWindow?.isVisible != true {
            filterFocusSnapshot = captureFocus()
        }

        if filterPanelWindow == nil {
            let size = NSSize(width: 320, height: 500)
            let frame = WindowPlacement.attachedPanelFrame(
                size: size,
                anchorFrame: mainWindow.frame,
                visibleFrames: currentVisibleScreenFrames()
            )

            let panel = TransparentWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = desiredWindowLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.title = "Advanced Filters"
            panel.setAccessibilityLabel("Advanced Filters")

            let panelView = FilterPanelView(frame: NSRect(origin: .zero, size: size))
            panelView.videoState = videoState

            let viewController = NSViewController()
            viewController.view = panelView
            panel.contentViewController = viewController

            panel.setAccessibilityIdentifier("window-filter-panel")
            panelView.setAccessibilityIdentifier("panel-filter-settings")

            filterPanelWindow = panel
            filterPanelView = panelView
            mainWindow.addChildWindow(panel, ordered: .above)
        }

        updateFilterPanelWindowFrame()
        filterPanelWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let panel = self.filterPanelWindow,
                  panel.isVisible,
                  let initialResponder = self.filterPanelView?.preferredInitialFirstResponder else {
                return
            }
            _ = panel.makeFirstResponder(initialResponder)
        }
    }

    private func hideFilterPanelWindow() {
        let shouldRestoreFocus = filterPanelWindow?.isKeyWindow == true
        filterPanelWindow?.orderOut(nil)
        let snapshot = filterFocusSnapshot
        filterFocusSnapshot = nil
        if shouldRestoreFocus {
            restoreFocus(from: snapshot)
        }
    }

    private func updateFilterPanelWindowFrame() {
        guard let filterPanelWindow = filterPanelWindow else { return }
        let frame = WindowPlacement.attachedPanelFrame(
            size: filterPanelWindow.frame.size,
            anchorFrame: mainWindow.frame,
            visibleFrames: currentVisibleScreenFrames()
        )
        filterPanelWindow.setFrame(frame, display: filterPanelWindow.isVisible)
    }

    private func updateDocumentationWindowFrame() {
        guard let documentationWindow else { return }
        let visibleFrames = currentVisibleScreenFrames()
        guard !visibleFrames.isEmpty else { return }
        let frame = WindowPlacement.clampAuxiliaryFrame(
            documentationWindow.frame,
            visibleFrames: visibleFrames
        )
        documentationWindow.setFrame(frame, display: documentationWindow.isVisible)
    }

    private func hideDocumentationWindow() {
        let shouldRestoreFocus = documentationWindow?.isKeyWindow == true
        documentationWindow?.orderOut(nil)
        let snapshot = documentationFocusSnapshot
        documentationFocusSnapshot = nil
        if shouldRestoreFocus {
            restoreFocus(from: snapshot)
        }
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
        _ = dispatch(.openVideo, origin: .menu)
    }

    @IBAction func resetZoom(_ sender: Any?) {
        _ = dispatch(.resetZoom, origin: .menu)
    }

    @IBAction func resetPosition(_ sender: Any?) {
        _ = dispatch(.resetView, origin: .menu)
    }

    @IBAction func toggleLock(_ sender: Any?) {
        _ = dispatch(.toggleLock, origin: .menu)
    }

    @IBAction func toggleAlwaysOnTop(_ sender: Any?) {
        _ = dispatch(.toggleAlwaysOnTop, origin: .menu)
    }

    @IBAction func togglePlayPause(_ sender: Any?) {
        _ = dispatch(.togglePlayPause, origin: .menu)
    }

    @IBAction func stepForward(_ sender: Any?) {
        _ = dispatch(.step(.forward, amount: 1), origin: .menu)
    }

    @IBAction func stepBackward(_ sender: Any?) {
        _ = dispatch(.step(.backward, amount: 1), origin: .menu)
    }

    @IBAction func showKeyboardShortcuts(_ sender: Any?) {
        _ = dispatch(.toggleShortcutSettings, origin: .menu)
    }

    @IBAction func openReframerHelp(_ sender: Any?) {
        _ = dispatch(.openDocumentation, origin: .menu)
    }

    private func openDocumentationWindow() {
        // Show documentation in a floating window above Reframer
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let helpURL = resourceURL
            .appendingPathComponent("Reframer.help")
            .appendingPathComponent("Contents/Resources/en.lproj/index.html")

        if documentationWindow?.isVisible != true {
            documentationFocusSnapshot = captureFocus()
        }

        // Create or reuse documentation window
        if documentationWindow == nil {
            let frame = centeredAuxiliaryFrame(size: NSSize(width: 700, height: 600))
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Reframer Documentation"
            window.level = desiredWindowLevel
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 480, height: 360)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.setAccessibilityIdentifier("window-documentation")

            let webView = WKWebView(frame: window.contentView!.bounds)
            webView.autoresizingMask = [.width, .height]
            webView.setAccessibilityIdentifier("documentation-content")
            webView.setAccessibilityLabel("Reframer documentation")
            window.contentView?.addSubview(webView)

            documentationWindow = window
            documentationWebView = webView
        }

        updateDocumentationWindowFrame()
        documentationWebView?.loadFileURL(helpURL, allowingReadAccessTo: resourceURL)
        documentationWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let window = self.documentationWindow,
                  window.isVisible,
                  let webView = self.documentationWebView else { return }
            _ = window.makeFirstResponder(webView)
        }
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
        _ = dispatch(.toggleMinimize, origin: .menu)
    }

    @IBAction func showFilterSettings(_ sender: Any?) {
        _ = dispatch(.toggleFilterPanel, origin: .menu)
    }

    @IBAction func resetFilterSettings(_ sender: Any?) {
        videoState.resetFilterSettings()
    }

}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === documentationWindow else { return }
        let snapshot = documentationFocusSnapshot
        documentationFocusSnapshot = nil
        restoreFocus(from: snapshot)
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
