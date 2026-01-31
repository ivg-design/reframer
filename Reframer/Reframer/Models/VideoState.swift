import SwiftUI
import AVFoundation
import Combine

class VideoState: ObservableObject {
    // Video loading
    @Published var videoURL: URL?
    @Published var isVideoLoaded: Bool = false

    // Playback
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentFrame: Int = 0
    @Published var totalFrames: Int = 0
    @Published var frameRate: Double = 30.0
    @Published var videoNaturalSize: CGSize = .zero

    // Volume
    @Published var volume: Float = 0.0 // Muted by default
    @Published var isMuted: Bool = true

    // Zoom & Pan
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    // Opacity
    @Published var opacity: Double = 1.0

    // Lock mode - disables pan/zoom gestures on video, controls remain active
    @Published var isLocked: Bool = false

    // Always on top
    @Published var isAlwaysOnTop: Bool = true

    // Help
    @Published var showHelp: Bool = false

    // Computed properties
    var zoomPercentage: Int {
        Int((zoomScale * 100).rounded())
    }

    var zoomPercentageValue: Double {
        Double(zoomScale * 100)
    }

    var opacityPercentage: Int {
        Int((opacity * 100).rounded())
    }

    var opacityPercentageValue: Double {
        opacity * 100
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    // MARK: - Methods

    func resetView() {
        zoomScale = 1.0
        panOffset = .zero
    }

    func setZoomPercentage(_ percentage: Int) {
        setZoomPercentage(Double(percentage))
    }

    func setZoomPercentage(_ percentage: Double) {
        let clamped = max(10.0, min(1000.0, percentage))
        zoomScale = CGFloat(clamped / 100.0)
    }

    func setOpacityPercentage(_ percentage: Int) {
        let clamped = max(2, min(100, percentage))
        opacity = Double(clamped) / 100.0
    }

    func adjustZoom(byPercent percent: Double) {
        let newPercentage = zoomPercentageValue + percent
        setZoomPercentage(newPercentage)
    }

    func toggleMute() {
        isMuted.toggle()
        volume = isMuted ? 0.0 : 0.5
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
