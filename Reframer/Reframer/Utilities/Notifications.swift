import Foundation

extension Notification.Name {
    static let openVideo = Notification.Name("openVideo")
    static let openYouTube = Notification.Name("openYouTube")
    static let frameStepForward = Notification.Name("frameStepForward")
    static let frameStepBackward = Notification.Name("frameStepBackward")
    static let seekToTime = Notification.Name("seekToTime")
    static let seekToFrame = Notification.Name("seekToFrame")
    static let avFoundationPlaybackFailed = Notification.Name("avFoundationPlaybackFailed")
}
