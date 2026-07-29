import Cocoa
import Combine

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

    private final class YouTubeConsentGate: NSObject {
        weak var loadButton: NSButton?

        @objc func consentChanged(_ sender: NSButton) {
            loadButton?.isEnabled = sender.state == .on
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
    private var shortcutsWindow: TransparentWindow?  // Keyboard shortcuts panel (H key)
    private weak var shortcutsView: HelpView?
    private var documentationWindow: NSWindow?        // Documentation browser (Help menu)
    private var documentationView: DocumentationView?
    private var filterPanelWindow: TransparentWindow?
    private weak var filterPanelView: FilterPanelView?
    private var alwaysOnTopMenuItem: NSMenuItem?

    let videoState = VideoState()
    private var cancellables = Set<AnyCancellable>()
    private let controlBarHeight = MainViewController.controlBarHeight
    private let mainWindowMinimumSize = NSSize(
        width: ControlBar.minimumWindowWidth,
        height: 360 + MainViewController.controlBarHeight
    )
    private let windowFrameDefaultsKey = "VideoOverlay.mainWindowFrame"
    private let windowFrameSchemaDefaultsKey = "VideoOverlay.mainWindowFrameSchema"
    private let shortcutSettingsSizeDefaultsKey =
        "VideoOverlay.shortcutSettingsWindowSize"
    private let youtubeConsentVersion = 1
    private let youtubeConsentVersionDefaultsKey =
        "OnlinePlayback.youtubeConsentVersion"
    private let integralControlBarFrameSchema = 2
    private var windowReclampWorkItem: DispatchWorkItem?
    private var isRepositioningWindows = false
    private var lockedWindowFrameGuard = LockedWindowFrameGuard()
    private var helpFocusSnapshot: FocusSnapshot?
    private var filterFocusSnapshot: FocusSnapshot?
    private var documentationFocusSnapshot: FocusSnapshot?
    private let youtubeComplianceClient = YouTubeComplianceClient()
    private var youtubePreflightTask: Task<Void, Never>?
    private var youtubePreflightID: UUID?
    private var youtubePreflightSelectionRevision: UInt64?

    private var mainViewController: MainViewController!
    private var shortcutMenuItems: [
        (item: NSMenuItem, action: ShortcutSettings.Action, factor: Int)
    ] = []

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        WebMPreparationSession.removeStaleOutputs()
        setupMainMenu()
        createMainWindow()
        observeWindowFrameChanges()
        setupGlobalShortcuts()
        observeState()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        #if DEBUG
        // Development-only convenience hook. The shipping app accepts video
        // URLs only through user-mediated open, drop, or Open With flows.
        if let testVideoPath = ProcessInfo.processInfo.environment["TEST_VIDEO_PATH"] {
            let url = URL(fileURLWithPath: testVideoPath)
            if FileManager.default.fileExists(atPath: testVideoPath) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.videoState.loadLocalMedia(url)
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowReclampWorkItem?.cancel()
        youtubePreflightTask?.cancel()
        youtubePreflightID = nil
        youtubePreflightSelectionRevision = nil
        persistShortcutSettingsWindowSize()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        globalHotKeyRegistrar?.invalidate()
        globalHotKeyRegistrar = nil
        if let monitor = localShortcutMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mainViewController?.shutdownMediaPlayback()
        videoState.discardPreparedMedia()
        WebMPreparationSession.removeStaleOutputs()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        reapplyOverlayWindowPolicy()
    }

    /// Handle files opened via "Open With" from Finder
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }

        // Check if it's a supported video format
        if VideoFormats.isSupported(url) {
            // Delay slightly to ensure windows are ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.videoState.loadLocalMedia(url)
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
        fileMenu.addItem(makeCommandMenuItem(
            title: "Open YouTube Video…",
            command: .openYouTube,
            keyEquivalent: "o",
            modifiers: [.command, .option]
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
            title: "Always on Top When Unlocked",
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
        // The video canvas and controls are one canonical system window. This
        // ensures macOS and third-party window managers always move and resize
        // the complete overlay.
        let windowSize = NSSize(
            width: ControlBar.preferredFullWidth,
            height: 560 + controlBarHeight
        )
        let defaultOrigin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2
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
        window.level = desiredOverlayWindowLevel
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
        mainViewController.windowToDrag = window
        mainViewController.onToggleLockRequest = { [weak self] in
            _ = self?.dispatch(.toggleLock, origin: .menu)
        }

        // Set frame again after content view controller to ensure size
        window.setFrame(windowFrame, display: true)

        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        mainWindow = window
    }

    private func loadSavedWindowFrame(defaultFrame: NSRect, visibleFrames: [NSRect]) -> NSRect {
        let preferences = videoState.preferenceStore
        let candidateFrame = WindowPlacement.restoredMainFrame(
            savedFrameDescription: preferences.string(forKey: windowFrameDefaultsKey),
            savedSchema: preferences.integer(forKey: windowFrameSchemaDefaultsKey),
            currentSchema: integralControlBarFrameSchema,
            defaultFrame: defaultFrame,
            controlBarHeight: controlBarHeight
        )
        let restoredFrame = WindowPlacement.clampMainFrame(
            candidateFrame,
            visibleFrames: visibleFrames,
            toolbarHeight: 0,
            minimumSize: mainWindowMinimumSize
        )

        // Persist the selected frame and schema before presenting the window.
        // A crash during first launch must not embed the legacy toolbar twice.
        preferences.set(
            NSStringFromRect(restoredFrame),
            forKey: windowFrameDefaultsKey
        )
        preferences.set(
            integralControlBarFrameSchema,
            forKey: windowFrameSchemaDefaultsKey
        )
        return restoredFrame
    }

    // MARK: - State Observation

    private func observeState() {
        videoState.mediaSelectionChanges
            .sink { [weak self] revision in
                guard let self,
                      let expected =
                        self.youtubePreflightSelectionRevision,
                      revision != expected else {
                    return
                }
                self.youtubePreflightTask?.cancel()
                self.youtubePreflightTask = nil
                self.youtubePreflightID = nil
                self.youtubePreflightSelectionRevision = nil
            }
            .store(in: &cancellables)

        videoState.reloadRequests
            .sink { [weak self] in
                guard let self,
                      let reference = YouTubeReloadPolicy.reference(
                        for: self.videoState.webMediaSource
                      ) else {
                    return
                }
                self.beginYouTubePreflight(for: reference)
            }
            .store(in: &cancellables)

        // Window presentation is one atomic policy. A locked overlay uses the
        // public status-bar tier, is non-resizable, and is pointer-transparent
        // regardless of the persisted unlocked-state Always on Top preference.
        Publishers.CombineLatest(
            videoState.$isLocked,
            videoState.$isAlwaysOnTop
        )
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .sink { [weak self] isLocked, isAlwaysOnTop in
                // These presentation properties are mutated only by AppKit
                // commands on the main thread. Keep this sink synchronous:
                // queuing it would leave a lock/unlock race in which an
                // external window-manager write could land before the frame
                // guard and pointer/move/resize policy changed.
                precondition(Thread.isMainThread)
                self?.applyOverlayWindowPolicy(
                    isLocked: isLocked,
                    isAlwaysOnTop: isAlwaysOnTop
                )
            }
            .store(in: &cancellables)

        videoState.$isAlwaysOnTop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnTop in
                self?.alwaysOnTopMenuItem?.state = isOnTop ? .on : .off
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

        // The whole locked window ignores pointer input. Never leave the app
        // in that state after its exact recovery chord becomes unavailable.
        if LockModeRecoveryPolicy.requiresForcedUnlock(
            isCurrentlyLocked: videoState.isLocked,
            isRecoveryRegistered: isGlobalLockRecoveryRegistered
        ) {
            videoState.isLocked = false
            DispatchQueue.main.async { [weak self] in
                self?.showLockRecoveryUnavailableAlert(
                    prefix: "Reframer unlocked the overlay because"
                )
            }
        }
    }

    private var globalLockRecoveryMatch: ShortcutMatch {
        ShortcutMatch(action: .globalToggleLock, variant: .primary)
    }

    private var isGlobalLockRecoveryRegistered: Bool {
        globalHotKeyRegistrar?.isRegistered(
            match: globalLockRecoveryMatch
        ) == true
    }

    /// Entering lock makes the complete overlay click-through, so an exact
    /// registered global recovery chord is a prerequisite. Unlocking is
    /// always permitted, including after an external registration failure.
    @discardableResult
    private func toggleLockWithRecoveryGuard() -> Bool {
        if videoState.isLocked {
            videoState.isLocked = false
            return true
        }
        guard LockModeRecoveryPolicy.canToggle(
            isCurrentlyLocked: videoState.isLocked,
            isRecoveryRegistered: isGlobalLockRecoveryRegistered
        ) else {
            showLockRecoveryUnavailableAlert(
                prefix: "Reframer could not lock the overlay because"
            )
            return false
        }
        videoState.isLocked = true
        return true
    }

    private func showLockRecoveryUnavailableAlert(prefix: String) {
        let configuredShortcut = videoState.shortcutSettings.displayString(
            for: .globalToggleLock
        )
        showErrorAlert(
            title: "Global Unlock Shortcut Unavailable",
            message: """
            \(prefix) its global unlock shortcut is not registered.

            Configured shortcut: \(configuredShortcut)

            Enable Global Shortcuts, enable the global lock binding, and resolve any registration conflict in Shortcut Settings before locking again.
            """
        )
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
            switch settings.record(stroke: ShortcutKeystroke(event: event)) {
            case .notRecording, .focusTraversal:
                return false
            case .consumed, .saved, .rejected:
                return true
            }
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
        case .openYouTube:
            promptForYouTubeVideo()
        case .togglePlayPause:
            videoState.togglePlaybackIntent()
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
            guard toggleLockWithRecoveryGuard() else { return false }
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
                isDocumentationVisible: documentationWindow?.isVisible == true,
                canTransformMedia: videoState.supportsVideoTransforms,
                canUseVideoFilters: videoState.supportsVideoFilters,
                canUseClickThroughLock: videoState.supportsClickThroughLock
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
        if menuItem.action == #selector(selectFilter(_:))
            || menuItem.action == #selector(clearQuickFilter(_:))
            || menuItem.action == #selector(resetFilterSettings(_:)) {
            return videoState.supportsVideoFilters
        }
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

    private var desiredOverlayWindowLevel: NSWindow.Level {
        OverlayWindowPolicy.resolve(
            isLocked: videoState.isLocked,
            isAlwaysOnTop: videoState.isAlwaysOnTop
        ).level
    }

    private var desiredAuxiliaryWindowLevel: NSWindow.Level {
        OverlayWindowPolicy.auxiliaryLevel(
            isLocked: videoState.isLocked,
            isAlwaysOnTop: videoState.isAlwaysOnTop
        )
    }

    private func applyOverlayWindowPolicy(
        isLocked: Bool,
        isAlwaysOnTop: Bool
    ) {
        guard let mainWindow else { return }
        let policy = OverlayWindowPolicy.resolve(
            isLocked: isLocked,
            isAlwaysOnTop: isAlwaysOnTop
        )

        let wasLocked = lockedWindowFrameGuard.lockedFrame != nil
        lockedWindowFrameGuard.updateLockState(
            isLocked: isLocked,
            currentFrame: mainWindow.frame
        )
        if isLocked {
            windowReclampWorkItem?.cancel()
            windowReclampWorkItem = nil
        }
        policy.apply(to: mainWindow)

        if isLocked {
            // Raising without activation keeps Reframer visible while keyboard
            // focus stays in the application beneath the click-through overlay.
            mainWindow.orderFrontRegardless()
        }
        applyAuxiliaryWindowLevels(
            isLocked: isLocked,
            isAlwaysOnTop: isAlwaysOnTop
        )
        orderVisibleAuxiliaryWindowsAboveOverlay()

        if wasLocked && !isLocked {
            // A display may have disappeared while the frame was intentionally
            // frozen. Recover it only after interaction is restored.
            DispatchQueue.main.async { [weak self] in
                self?.reclampWindowsToVisibleScreens()
            }
        }
    }

    private func reapplyOverlayWindowPolicy() {
        applyOverlayWindowPolicy(
            isLocked: videoState.isLocked,
            isAlwaysOnTop: videoState.isAlwaysOnTop
        )
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        reapplyOverlayWindowPolicy()
    }

    @objc private func workspaceApplicationDidActivate(_ notification: Notification) {
        guard videoState.isLocked else { return }
        reapplyOverlayWindowPolicy()
    }

    private func applyAuxiliaryWindowLevels(
        isLocked: Bool,
        isAlwaysOnTop: Bool
    ) {
        let level = OverlayWindowPolicy.auxiliaryLevel(
            isLocked: isLocked,
            isAlwaysOnTop: isAlwaysOnTop
        )
        shortcutsWindow?.level = level
        filterPanelWindow?.level = level
        documentationWindow?.level = level
    }

    private func orderVisibleAuxiliaryWindowsAboveOverlay() {
        guard let mainWindow else { return }
        for window in [shortcutsWindow, filterPanelWindow, documentationWindow]
        where window?.isVisible == true {
            window?.order(.above, relativeTo: mainWindow.windowNumber)
        }
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
        if let restorationFrame = lockedWindowFrameGuard.restorationFrame(
            for: mainWindow.frame
        ) {
            isRepositioningWindows = true
            mainWindow.setFrame(restorationFrame, display: true, animate: false)
            isRepositioningWindows = false
            return
        }
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
        guard !videoState.isLocked else { return }
        windowReclampWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reclampWindowsToVisibleScreens()
        }
        windowReclampWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func reclampWindowsToVisibleScreens() {
        guard let mainWindow,
              !isRepositioningWindows,
              !videoState.isLocked else {
            return
        }
        let visibleFrames = currentVisibleScreenFrames()
        guard !visibleFrames.isEmpty else { return }

        windowReclampWorkItem?.cancel()
        windowReclampWorkItem = nil
        isRepositioningWindows = true
        defer { isRepositioningWindows = false }

        let mainFrame = WindowPlacement.clampMainFrame(
            mainWindow.frame,
            visibleFrames: visibleFrames,
            toolbarHeight: 0,
            minimumSize: mainWindowMinimumSize
        )
        if mainFrame != mainWindow.frame {
            mainWindow.setFrame(mainFrame, display: true)
        }

        updateHelpWindowFrame()
        updateFilterPanelWindowFrame()
        updateDocumentationWindowFrame()
        saveWindowFrame()
    }

    private func saveWindowFrame() {
        guard let mainWindow = mainWindow,
              WindowPlacement.isUsableFrame(mainWindow.frame) else { return }
        let frameString = NSStringFromRect(mainWindow.frame)
        videoState.preferenceStore.set(frameString, forKey: windowFrameDefaultsKey)
        videoState.preferenceStore.set(
            integralControlBarFrameSchema,
            forKey: windowFrameSchemaDefaultsKey
        )
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

    private func shortcutSettingsSizeLimits() -> (minimum: NSSize, maximum: NSSize) {
        let visibleFrames = currentVisibleScreenFrames()
        let anchorFrame = WindowPlacement.bestVisibleFrame(
            for: mainWindow.frame,
            among: visibleFrames
        ) ?? visibleFrames.first
        let screenMaximum = NSSize(
            width: max(1, (anchorFrame?.width ?? HelpView.maximumWindowSize.width) - 40),
            height: max(1, (anchorFrame?.height ?? HelpView.maximumWindowSize.height) - 40)
        )
        let maximum = NSSize(
            width: min(HelpView.maximumWindowSize.width, screenMaximum.width),
            height: min(HelpView.maximumWindowSize.height, screenMaximum.height)
        )
        let minimum = NSSize(
            width: min(HelpView.minimumWindowSize.width, maximum.width),
            height: min(HelpView.minimumWindowSize.height, maximum.height)
        )
        return (minimum, maximum)
    }

    private func clampShortcutSettingsSize(
        _ size: NSSize,
        limits: (minimum: NSSize, maximum: NSSize)
    ) -> NSSize {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return NSSize(
                width: min(
                    max(HelpView.preferredWindowSize.width, limits.minimum.width),
                    limits.maximum.width
                ),
                height: min(
                    max(HelpView.preferredWindowSize.height, limits.minimum.height),
                    limits.maximum.height
                )
            )
        }
        return NSSize(
            width: min(max(size.width, limits.minimum.width), limits.maximum.width),
            height: min(max(size.height, limits.minimum.height), limits.maximum.height)
        )
    }

    private func restoredShortcutSettingsSize(
        limits: (minimum: NSSize, maximum: NSSize)
    ) -> NSSize {
        let storedSize = videoState.preferenceStore
            .string(forKey: shortcutSettingsSizeDefaultsKey)
            .map(NSSizeFromString)
        return clampShortcutSettingsSize(
            storedSize ?? HelpView.preferredWindowSize,
            limits: limits
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
            let sizeLimits = shortcutSettingsSizeLimits()
            let size = restoredShortcutSettingsSize(limits: sizeLimits)
            let frame = centeredAuxiliaryFrame(size: size)

            let panel = TransparentWindow(
                contentRect: frame,
                styleMask: ShortcutSettingsWindowConfiguration.styleMask,
                backing: .buffered,
                defer: false
            )

            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = desiredAuxiliaryWindowLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.contentMinSize = sizeLimits.minimum
            panel.contentMaxSize = sizeLimits.maximum
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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(shortcutSettingsWindowDidEndLiveResize),
                name: NSWindow.didEndLiveResizeNotification,
                object: panel
            )
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
        persistShortcutSettingsWindowSize()
        shortcutsWindow?.orderOut(nil)
        let snapshot = helpFocusSnapshot
        helpFocusSnapshot = nil
        if shouldRestoreFocus {
            restoreFocus(from: snapshot)
        }
    }

    private func updateHelpWindowFrame() {
        guard let shortcutsWindow = shortcutsWindow else { return }
        let sizeLimits = shortcutSettingsSizeLimits()
        shortcutsWindow.contentMinSize = sizeLimits.minimum
        shortcutsWindow.contentMaxSize = sizeLimits.maximum
        let size = clampShortcutSettingsSize(
            shortcutsWindow.frame.size,
            limits: sizeLimits
        )
        let frame = centeredAuxiliaryFrame(size: size)
        shortcutsWindow.setFrame(frame, display: shortcutsWindow.isVisible)
    }

    @objc private func shortcutSettingsWindowDidEndLiveResize(
        _ notification: Notification
    ) {
        guard let window = notification.object as? NSWindow,
              window === shortcutsWindow else {
            return
        }
        persistShortcutSettingsWindowSize()
    }

    private func persistShortcutSettingsWindowSize() {
        guard let window = shortcutsWindow else {
            return
        }
        let size = clampShortcutSettingsSize(
            window.frame.size,
            limits: shortcutSettingsSizeLimits()
        )
        videoState.preferenceStore.set(
            NSStringFromSize(size),
            forKey: shortcutSettingsSizeDefaultsKey
        )
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
            panel.level = desiredAuxiliaryWindowLevel
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
                self?.videoState.loadLocalMedia(url)
            }
        } else {
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                self?.videoState.loadLocalMedia(url)
            }
        }
    }

    private func promptForYouTubeVideo() {
        let alert = NSAlert()
        alert.messageText = "Open YouTube Video"
        alert.informativeText =
            "Paste a public or unlisted YouTube video link. Reframer checks its audience status, then loads YouTube only after your consent. \(YouTubeVideoReference.qualityDisclosure)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Load Video")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField()
        field.placeholderString = "https://www.youtube.com/watch?v=…"
        field.setAccessibilityLabel("YouTube video URL")
        field.widthAnchor.constraint(equalToConstant: 460).isActive = true

        let consentCheckbox = NSButton(
            checkboxWithTitle:
                "I agree to Reframer’s YouTube Privacy Notice and Terms",
            target: nil,
            action: nil
        )
        let hasAcceptedCurrentTerms =
            videoState.preferenceStore.integer(
                forKey: youtubeConsentVersionDefaultsKey
            ) >= youtubeConsentVersion
        consentCheckbox.state = hasAcceptedCurrentTerms ? .on : .off
        consentCheckbox.setAccessibilityHelp(
            "Consent is required before Reframer contacts the YouTube Data API or player."
        )

        let consentGate = YouTubeConsentGate()
        consentGate.loadButton = alert.buttons.first
        consentCheckbox.target = consentGate
        consentCheckbox.action = #selector(
            YouTubeConsentGate.consentChanged(_:)
        )
        alert.buttons.first?.isEnabled = hasAcceptedCurrentTerms

        let links = NSStackView(views: [
            makeYouTubePolicyLink(
                title: "Privacy Notice",
                action: #selector(openYouTubePrivacyNotice)
            ),
            makeYouTubePolicyLink(
                title: "YouTube Terms",
                action: #selector(openYouTubeTerms)
            ),
            makeYouTubePolicyLink(
                title: "Google Privacy",
                action: #selector(openGooglePrivacy)
            )
        ])
        links.orientation = .horizontal
        links.spacing = 14
        links.alignment = .centerY

        let accessory = NSStackView(
            views: [field, consentCheckbox, links]
        )
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.frame = NSRect(x: 0, y: 0, width: 460, height: 76)
        alert.accessoryView = accessory

        let completion: (NSApplication.ModalResponse) -> Void = {
            [weak self, weak field, weak consentCheckbox, consentGate] response in
            _ = consentGate
            guard response == .alertFirstButtonReturn,
                  consentCheckbox?.state == .on,
                  let value = field?.stringValue,
                  let reference = YouTubeVideoReference.parse(value) else {
                if response == .alertFirstButtonReturn {
                    self?.showErrorAlert(
                        title: "Invalid YouTube Link",
                        message:
                            "Paste one public or unlisted YouTube video URL, not a playlist, channel, or search page."
                    )
                }
                return
            }
            guard let self else { return }
            self.videoState.preferenceStore.set(
                self.youtubeConsentVersion,
                forKey: self.youtubeConsentVersionDefaultsKey
            )
            self.beginYouTubePreflight(for: reference)
        }

        if let mainWindow {
            alert.beginSheetModal(for: mainWindow, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func beginYouTubePreflight(
        for reference: YouTubeVideoReference
    ) {
        youtubePreflightTask?.cancel()
        let requestID = UUID()
        let selectionRevision = videoState.beginPendingMediaSelection(
            displayName: "YouTube video"
        )
        youtubePreflightID = requestID
        youtubePreflightSelectionRevision = selectionRevision
        youtubePreflightTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.youtubePreflightID == requestID {
                    self.youtubePreflightID = nil
                    self.youtubePreflightSelectionRevision = nil
                    self.youtubePreflightTask = nil
                }
            }
            do {
                let authorization = try await
                    self.youtubeComplianceClient.authorize(reference)
                try Task.checkCancellation()
                guard self.youtubePreflightID == requestID,
                      self.videoState.isCurrentMediaSelection(
                        selectionRevision
                      ) else {
                    return
                }
                _ = self.videoState.loadYouTube(
                    authorization,
                    ifCurrent: selectionRevision
                )
            } catch is CancellationError {
                return
            } catch let error as URLError
                where error.code == .cancelled {
                return
            } catch {
                guard self.youtubePreflightID == requestID,
                      self.videoState.isCurrentMediaSelection(
                        selectionRevision
                      ) else {
                    return
                }
                self.videoState.cancelPendingMediaSelection(
                    selectionRevision
                )
                self.showErrorAlert(
                    title: "YouTube Video Not Loaded",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func makeYouTubePolicyLink(
        title: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.contentTintColor = .linkColor
        return button
    }

    @objc private func openYouTubePrivacyNotice() {
        openDocumentationWindow(pageName: "youtube-privacy.html")
    }

    @objc private func openYouTubeTerms() {
        NSWorkspace.shared.open(
            URL(string: "https://www.youtube.com/t/terms")!
        )
    }

    @objc private func openGooglePrivacy() {
        NSWorkspace.shared.open(
            URL(string: "https://policies.google.com/privacy")!
        )
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

    private func openDocumentationWindow(pageName: String? = nil) {
        let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let helpRootURL = resourceURL
            .appendingPathComponent("Reframer.help")
            .appendingPathComponent("Contents/Resources/en.lproj")

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
            window.level = desiredAuxiliaryWindowLevel
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 480, height: 360)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.setAccessibilityIdentifier("window-documentation")

            let documentationView = DocumentationView(rootURL: helpRootURL)
            let viewController = NSViewController()
            viewController.view = documentationView
            window.contentViewController = viewController

            documentationWindow = window
            self.documentationView = documentationView
        }

        updateDocumentationWindowFrame()
        if let pageName {
            _ = documentationView?.navigate(
                to: helpRootURL.appendingPathComponent(pageName)
            )
        } else {
            documentationView?.showHome()
        }
        documentationWindow?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let window = self.documentationWindow,
                  window.isVisible,
                  let documentationView = self.documentationView else { return }
            _ = window.makeFirstResponder(
                documentationView.preferredInitialFirstResponder
            )
        }
    }

    @IBAction func selectFilter(_ sender: NSMenuItem) {
        guard videoState.supportsVideoFilters,
              let filter = sender.representedObject as? VideoFilter else {
            return
        }
        // Single selection - same as toolbar behavior
        videoState.setQuickFilter(filter)
    }

    @IBAction func clearQuickFilter(_ sender: Any?) {
        guard videoState.supportsVideoFilters else { return }
        videoState.setQuickFilter(nil)
    }

    @IBAction func toggleMinimize(_ sender: Any?) {
        _ = dispatch(.toggleMinimize, origin: .menu)
    }

    @IBAction func showFilterSettings(_ sender: Any?) {
        _ = dispatch(.toggleFilterPanel, origin: .menu)
    }

    @IBAction func resetFilterSettings(_ sender: Any?) {
        guard videoState.supportsVideoFilters else { return }
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
        noneItem.isEnabled = videoState.supportsVideoFilters
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
            item.isEnabled = videoState.supportsVideoFilters
            menu.insertItem(item, at: index + 1)  // +1 for "None" item
        }
    }
}
