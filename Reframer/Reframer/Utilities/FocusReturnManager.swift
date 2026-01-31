import AppKit

final class FocusReturnManager {
    static let shared = FocusReturnManager()

    private var lastNonOverlayApp: NSRunningApplication?
    private var activationObserver: Any?

    private init() {}

    func startTracking() {
        guard activationObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.lastNonOverlayApp = app
            }
        }
    }

    func returnFocusToPreviousApp() {
        guard let app = lastNonOverlayApp else { return }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
