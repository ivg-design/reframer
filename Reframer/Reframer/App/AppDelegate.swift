import Cocoa
import SwiftUI
import Combine

// Custom window that can become key
class TransparentWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    var mainWindow: TransparentWindow!
    private var controlWindow: TransparentWindow!
    private var helpWindow: TransparentWindow?
    var videoState = VideoState()
    private var cancellables = Set<AnyCancellable>()
    private let controlWindowHeight: CGFloat = 64

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow()
        FocusReturnManager.shared.startTracking()
        setupGlobalShortcuts()
        ensureInstalledInApplications()
        observeState()
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

    private func createWindow() {
        let window = TransparentWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.center()

        let contentView = ContentView().environmentObject(videoState)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        mainWindow = window
        createControlWindow()
        observeWindowFrameChanges()
    }

    private func observeState() {
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
    }

    private func setupGlobalShortcuts() {
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKey(event)
        }

        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleGlobalKey(event) == true {
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

        if hasCommand && hasShift && event.keyCode == 37 {
            NotificationCenter.default.post(name: .toggleLock, object: nil)
            return true
        }

        if hasCommand && event.keyCode == 116 {
            NotificationCenter.default.post(name: .frameStepForward, object: hasShift ? 10 : 1)
            return true
        }

        if hasCommand && event.keyCode == 121 {
            NotificationCenter.default.post(name: .frameStepBackward, object: hasShift ? 10 : 1)
            return true
        }

        return false
    }

    private func createControlWindow() {
        let mainFrame = mainWindow.frame
        let controlFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY,
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
        window.isMovableByWindowBackground = false

        let controlView = ControlWindowView().environmentObject(videoState)
        let hostingView = NSHostingView(rootView: controlView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        window.contentView = hostingView

        controlWindow = window
        mainWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
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
    }

    @objc private func mainWindowFrameDidChange(_ notification: Notification) {
        updateControlWindowFrame()
        updateHelpWindowFrame()
    }

    private func updateControlWindowFrame() {
        guard let mainWindow = mainWindow, let controlWindow = controlWindow else { return }
        let mainFrame = mainWindow.frame
        let controlFrame = NSRect(
            x: mainFrame.minX,
            y: mainFrame.minY,
            width: mainFrame.width,
            height: controlWindowHeight
        )
        controlWindow.setFrame(controlFrame, display: true)
    }

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

            let helpView = HelpModalView().environmentObject(videoState)
            let hostingView = NSHostingView(rootView: helpView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear
            panel.contentView = hostingView

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
