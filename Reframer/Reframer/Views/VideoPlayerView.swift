import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    @EnvironmentObject var videoState: VideoState
    @StateObject private var playerManager = VideoPlayerManager()

    var body: some View {
        GeometryReader { geometry in
            VideoNSView(
                playerManager: playerManager,
                videoState: videoState,
                size: geometry.size
            )
        }
        .onAppear {
            if let url = videoState.videoURL {
                playerManager.loadVideo(url: url, videoState: videoState)
            }
        }
        .onChange(of: videoState.videoURL) { _, newURL in
            if let url = newURL {
                playerManager.loadVideo(url: url, videoState: videoState)
            }
        }
        .onChange(of: videoState.isPlaying) { _, isPlaying in
            if isPlaying { playerManager.play() } else { playerManager.pause() }
        }
        .onChange(of: videoState.volume) { _, volume in
            playerManager.setVolume(volume)
        }
        .onReceive(NotificationCenter.default.publisher(for: .frameStepForward)) { n in
            playerManager.stepFrame(forward: true, amount: (n.object as? Int) ?? 1, videoState: videoState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .frameStepBackward)) { n in
            playerManager.stepFrame(forward: false, amount: (n.object as? Int) ?? 1, videoState: videoState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .seekToTimeInternal)) { n in
            if let time = n.object as? Double {
                playerManager.scrub(to: time, videoState: videoState)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seekToFrameInternal)) { n in
            if let frame = n.object as? Int {
                playerManager.seekToFrame(frame, videoState: videoState)
            }
        }
    }
}

// MARK: - NSView wrapper for mouse events

struct VideoNSView: NSViewRepresentable {
    @ObservedObject var playerManager: VideoPlayerManager
    @ObservedObject var videoState: VideoState
    let size: CGSize

    func makeNSView(context: Context) -> VideoMouseView {
        let view = VideoMouseView()
        view.videoState = videoState
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let playerLayer = AVPlayerLayer()
        playerLayer.backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
        view.playerLayer = playerLayer
        view.layer?.addSublayer(playerLayer)

        return view
    }

    func updateNSView(_ view: VideoMouseView, context: Context) {
        view.videoState = videoState
        view.playerLayer?.player = playerManager.avPlayer
        view.size = size

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let bounds = CGRect(origin: .zero, size: size)
        let videoRect: CGRect
        if videoState.videoNaturalSize != .zero {
            videoRect = AVMakeRect(aspectRatio: videoState.videoNaturalSize, insideRect: bounds)
        } else {
            videoRect = bounds
        }

        // Anchor at top-left of the video rect (macOS coords: origin bottom-left)
        view.playerLayer?.frame = videoRect
        view.playerLayer?.anchorPoint = CGPoint(x: 0, y: 1)
        view.playerLayer?.position = CGPoint(x: videoRect.minX, y: videoRect.maxY)

        // Apply scale and translate
        var transform = CATransform3DIdentity
        transform = CATransform3DScale(transform, videoState.zoomScale, videoState.zoomScale, 1)
        transform = CATransform3DTranslate(
            transform,
            videoState.panOffset.width / videoState.zoomScale,
            videoState.panOffset.height / videoState.zoomScale,
            0
        )
        view.playerLayer?.transform = transform

        CATransaction.commit()
    }
}

// MARK: - Custom NSView for mouse handling

class VideoMouseView: NSView {
    weak var videoState: VideoState?
    var playerLayer: AVPlayerLayer?
    var size: CGSize = .zero
    private var dragStart: NSPoint = .zero
    private var panStart: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Mouse click+drag for panning (works at any zoom level)

    override func mouseDown(with event: NSEvent) {
        guard let videoState = videoState, !videoState.isLocked else { return }
        dragStart = event.locationInWindow
        panStart = videoState.panOffset
    }

    override func mouseDragged(with event: NSEvent) {
        guard let videoState = videoState, !videoState.isLocked else { return }
        let current = event.locationInWindow
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y

        DispatchQueue.main.async {
            videoState.panOffset = CGSize(
                width: self.panStart.width + dx,
                height: self.panStart.height - dy  // Flip Y for SwiftUI coordinates
            )
        }
    }

    // MARK: - Scroll wheel: frame stepping or zoom

    override func scrollWheel(with event: NSEvent) {
        guard let videoState = videoState, !videoState.isLocked else { return }

        let delta = event.scrollingDeltaY
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCmd = event.modifierFlags.contains(.command)

        DispatchQueue.main.async {
            guard delta != 0 else { return }
            let direction = delta < 0 ? 1.0 : -1.0
            let magnitude: Double
            if event.hasPreciseScrollingDeltas {
                magnitude = max(0.25, min(4.0, abs(delta) / 10.0))
            } else {
                magnitude = 1.0
            }
            if hasCmd && hasShift {
                // Fine zoom: 0.1% per tick
                videoState.adjustZoom(byPercent: direction * 0.1 * magnitude)
            } else if hasShift {
                // Zoom: 5% per tick
                videoState.adjustZoom(byPercent: direction * 5.0 * magnitude)
            } else {
                // Frame stepping
                if delta > 0.5 {
                    NotificationCenter.default.post(name: .frameStepBackward, object: 1)
                } else if delta < -0.5 {
                    NotificationCenter.default.post(name: .frameStepForward, object: 1)
                }
            }
        }
    }
}

// MARK: - Video Player Manager

class VideoPlayerManager: ObservableObject {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    
    private var timeObserver: Any?
    private weak var videoState: VideoState?

    var avPlayer: AVPlayer? { player }

    func loadVideo(url: URL, videoState: VideoState) {
        self.videoState = videoState
        cleanup()

        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = videoState.volume

        Task {
            do {
                let duration = try await asset.load(.duration)
                let tracks = try await asset.load(.tracks)

                await MainActor.run {
                    videoState.duration = CMTimeGetSeconds(duration)
                    videoState.totalFrames = Int(videoState.duration * videoState.frameRate)
                }

                if let track = tracks.first(where: { $0.mediaType == .video }) {
                    let fps = try? await track.load(.nominalFrameRate)
                    let (naturalSize, preferredTransform) = try await track.load(.naturalSize, .preferredTransform)
                    let transformedSize = naturalSize.applying(preferredTransform)
                    let resolvedSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

                    await MainActor.run {
                        if let fps = fps {
                            let resolvedFPS = fps > 0 ? Double(fps) : 30.0
                            videoState.frameRate = resolvedFPS
                            videoState.totalFrames = Int(videoState.duration * resolvedFPS)
                        }
                        videoState.videoNaturalSize = resolvedSize
                    }
                }
            } catch {
                print("Error: \(error)")
            }
        }

        let interval = CMTime(value: 1, timescale: Int32(max(30.0, videoState.frameRate)))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let vs = self?.videoState else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite {
                vs.currentTime = sec
                vs.currentFrame = Int(sec * vs.frameRate)
            }
        }

        objectWillChange.send()
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    // Fast scrubbing (for slider) - uses tolerance for speed
    func scrub(to time: Double, videoState: VideoState) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.currentItem?.cancelPendingSeeks()
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        videoState.currentTime = time
        videoState.currentFrame = Int(time * videoState.frameRate)
    }

    // Frame-accurate seek (for frame input)
    func seekToFrame(_ frame: Int, videoState: VideoState) {
        let time = Double(frame) / videoState.frameRate
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                videoState.currentFrame = frame
                videoState.currentTime = time
            }
        }
    }

    // Frame stepping - frame accurate
    func stepFrame(forward: Bool, amount: Int, videoState: VideoState) {
        pause()
        videoState.isPlaying = false

        let delta = forward ? amount : -amount
        let newFrame = max(0, min(videoState.totalFrames - 1, videoState.currentFrame + delta))
        seekToFrame(newFrame, videoState: videoState)
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    private func cleanup() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
    }

    deinit { cleanup() }
}
