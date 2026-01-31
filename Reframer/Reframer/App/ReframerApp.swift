import SwiftUI
import Combine

@main
struct VideoOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - window is created in AppDelegate
        Settings {
            EmptyView()
        }
    }
}

extension Notification.Name {
    static let openVideo = Notification.Name("openVideo")
    static let toggleLock = Notification.Name("toggleLock")
    static let frameStepForward = Notification.Name("frameStepForward")
    static let frameStepBackward = Notification.Name("frameStepBackward")
}
