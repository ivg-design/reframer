import Cocoa
import AVFoundation
import CoreImage
import Combine

/// Pure AppKit video view with zoom, pan, and mouse handling
class VideoView: NSView {

    // MARK: - Properties

    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var currentAsset: AVURLAsset?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    // Core Image context for filter processing (reused for performance)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    // Drag state for Ctrl+drag panning
    private var dragStart: NSPoint = .zero
    private var panStart: CGSize = .zero
    private var isPanning: Bool = false  // Track if we started a pan operation

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        playerLayer.backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        // Observe zoom changes
        state.$zoomScale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTransform() }
            .store(in: &cancellables)

        // Observe pan changes
        state.$panOffset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTransform() }
            .store(in: &cancellables)

        // Observe video size changes
        state.$videoNaturalSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTransform() }
            .store(in: &cancellables)

        // Observe playback state
        state.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                if isPlaying { self?.player?.play() } else { self?.player?.pause() }
            }
            .store(in: &cancellables)

        // Observe volume
        state.$volume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.player?.volume = volume
            }
            .store(in: &cancellables)

        // Observe video URL
        state.$videoURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                if let url = url {
                    self?.loadVideo(url: url)
                }
            }
            .store(in: &cancellables)

        // Listen for seek notifications
        NotificationCenter.default.publisher(for: .seekToTime)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Double }
            .sink { [weak self] time in self?.scrub(to: time) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .seekToFrame)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Int }
            .sink { [weak self] frame in self?.seekToFrame(frame) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .frameStepForward)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Int }
            .sink { [weak self] amount in self?.stepFrame(forward: true, amount: amount) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .frameStepBackward)
            .receive(on: DispatchQueue.main)
            .compactMap { $0.object as? Int }
            .sink { [weak self] amount in self?.stepFrame(forward: false, amount: amount) }
            .store(in: &cancellables)

        // Observe filter changes
        state.$activeFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFilter() }
            .store(in: &cancellables)

        state.$filterSettings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFilter() }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateTransform()
    }

    private func updateTransform() {
        guard let state = videoState else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Calculate base video rect (aspect-fit)
        let videoRect: CGRect
        if state.videoNaturalSize != .zero {
            videoRect = AVMakeRect(aspectRatio: state.videoNaturalSize, insideRect: bounds)
        } else {
            videoRect = bounds
        }

        // Reset transform before setting geometry
        playerLayer.transform = CATransform3DIdentity

        // Set bounds (size) and position separately for proper transform behavior
        playerLayer.bounds = CGRect(origin: .zero, size: videoRect.size)

        // Anchor at top-left of video (0, 1 in flipped coordinates where Y=0 is bottom)
        playerLayer.anchorPoint = CGPoint(x: 0, y: 1)

        // Position the anchor point at the top-left of where video should be
        playerLayer.position = CGPoint(x: videoRect.minX, y: videoRect.maxY)

        // Build transform: scale first (around anchor), then translate
        var transform = CATransform3DIdentity

        // Scale around anchor point (top-left of video)
        transform = CATransform3DScale(transform, state.zoomScale, state.zoomScale, 1)

        // Then apply pan (in scaled coordinates, so divide by scale)
        transform = CATransform3DTranslate(
            transform,
            state.panOffset.width / state.zoomScale,
            state.panOffset.height / state.zoomScale,
            0
        )

        playerLayer.transform = transform

        CATransaction.commit()
    }

    // MARK: - Video Loading

    func loadVideo(url: URL) {
        cleanup()
        guard let state = videoState else { return }

        // Reset state for new video
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        lastSeekTime = -1  // Allow scrubbing from the start

        let asset = AVURLAsset(url: url)
        currentAsset = asset
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = state.volume
        playerLayer.player = player

        // Apply current filter if any
        applyCurrentFilter()

        // Load asset properties
        Task { [weak self, weak state] in
            do {
                let duration = try await asset.load(.duration)
                let tracks = try await asset.load(.tracks)

                await MainActor.run {
                    guard let state = state else { return }
                    state.duration = CMTimeGetSeconds(duration)
                    state.totalFrames = Int(state.duration * state.frameRate)
                }

                if let track = tracks.first(where: { $0.mediaType == .video }) {
                    let fps = try? await track.load(.nominalFrameRate)
                    let (naturalSize, preferredTransform) = try await track.load(.naturalSize, .preferredTransform)
                    let transformedSize = naturalSize.applying(preferredTransform)
                    let resolvedSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

                    await MainActor.run {
                        guard let state = state else { return }
                        if let fps = fps, fps > 0 {
                            state.frameRate = Double(fps)
                            state.totalFrames = Int(state.duration * Double(fps))
                        }
                        state.videoNaturalSize = resolvedSize
                    }
                }
            } catch {
                await MainActor.run {
                    self?.showVideoLoadError(error)
                }
            }
        }

        // Time observer for playback position
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let state = self?.videoState else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite {
                state.currentTime = sec
                state.currentFrame = Int(sec * state.frameRate)
            }
        }
    }

    private var lastSeekTime: Double = -1

    func scrub(to time: Double) {
        guard let state = videoState else { return }

        // Clamp to valid range
        let clampedTime = max(0, min(state.duration, time))

        // Avoid redundant seeks to the same time
        if abs(clampedTime - lastSeekTime) < 0.01 { return }
        lastSeekTime = clampedTime

        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player?.currentItem?.cancelPendingSeeks()
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        state.currentTime = clampedTime
        state.currentFrame = Int(clampedTime * state.frameRate)
    }

    func seekToFrame(_ frame: Int) {
        guard let state = videoState else { return }
        let time = Double(frame) / state.frameRate
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak state] _ in
            DispatchQueue.main.async {
                state?.currentFrame = frame
                state?.currentTime = time
            }
        }
    }

    func stepFrame(forward: Bool, amount: Int) {
        guard let state = videoState else { return }
        player?.pause()
        state.isPlaying = false

        let delta = forward ? amount : -amount
        let newFrame = max(0, min(state.totalFrames - 1, state.currentFrame + delta))
        seekToFrame(newFrame)
    }

    private func showVideoLoadError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to Load Video"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
        videoState?.isVideoLoaded = false
    }

    private func cleanup() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
        currentAsset = nil
    }

    deinit {
        cleanup()
    }

    // MARK: - Video Filters

    private func applyCurrentFilter() {
        guard let asset = currentAsset,
              let state = videoState,
              let playerItem = playerItem else { return }

        // If no filter, remove any existing composition
        guard state.activeFilter != .none else {
            playerItem.videoComposition = nil
            return
        }

        // Create filter
        guard let filter = state.activeFilter.createFilter(settings: state.filterSettings) else {
            playerItem.videoComposition = nil
            return
        }

        // Get video track to determine size and timing
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let tracks = try await asset.load(.tracks)
                guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else { return }

                let (naturalSize, preferredTransform, nominalFrameRate) = try await videoTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate)
                let transformedSize = naturalSize.applying(preferredTransform)
                let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

                await MainActor.run {
                    self.createVideoComposition(
                        for: playerItem,
                        renderSize: renderSize,
                        frameRate: nominalFrameRate,
                        filter: filter
                    )
                }
            } catch {
                print("Error loading video track for filter: \(error)")
            }
        }
    }

    private func createVideoComposition(
        for playerItem: AVPlayerItem,
        renderSize: CGSize,
        frameRate: Float,
        filter: CIFilter
    ) {
        let composition = AVMutableVideoComposition(asset: playerItem.asset, applyingCIFiltersWithHandler: { [weak self] request in
            guard let self = self else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            // Get source image
            let sourceImage = request.sourceImage

            // Apply filter
            filter.setValue(sourceImage, forKey: kCIInputImageKey)

            // Get output or fall back to source
            if let outputImage = filter.outputImage {
                // Clamp to extent to prevent infinite extent issues with some filters
                let clampedImage = outputImage.clamped(to: sourceImage.extent)
                request.finish(with: clampedImage, context: self.ciContext)
            } else {
                request.finish(with: sourceImage, context: self.ciContext)
            }
        })

        composition.renderSize = renderSize

        // Set frame duration based on video frame rate
        if frameRate > 0 {
            composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        } else {
            composition.frameDuration = CMTime(value: 1, timescale: 30)
        }

        playerItem.videoComposition = composition
    }

    // MARK: - Mouse Handling

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let state = videoState, !state.isLocked else { return }

        // Only start panning if Ctrl is held (otherwise let window drag work)
        if event.modifierFlags.contains(.control) {
            isPanning = true
            dragStart = event.locationInWindow
            panStart = state.panOffset
        } else {
            isPanning = false
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = videoState, !state.isLocked, isPanning else { return }

        let current = event.locationInWindow
        let dx = current.x - dragStart.x
        let dy = current.y - dragStart.y

        state.panOffset = CGSize(
            width: panStart.width + dx,
            height: panStart.height + dy
        )
    }

    override func mouseUp(with event: NSEvent) {
        isPanning = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard let state = videoState, !state.isLocked else { return }

        let hasShift = event.modifierFlags.contains(.shift)
        let hasCmd = event.modifierFlags.contains(.command)

        // macOS swaps scroll axis when Shift is held, so check both axes
        let deltaY = event.scrollingDeltaY
        let deltaX = event.scrollingDeltaX
        let delta = hasShift ? (abs(deltaX) > abs(deltaY) ? deltaX : deltaY) : deltaY

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
            state.adjustZoom(byPercent: direction * 0.1 * magnitude)
        } else if hasShift {
            // Zoom: 5% per tick
            state.adjustZoom(byPercent: direction * 5.0 * magnitude)
        } else {
            // Frame stepping
            if delta > 0.5 {
                NotificationCenter.default.post(name: .frameStepBackward, object: 1)
            } else if delta < -0.5 {
                NotificationCenter.default.post(name: .frameStepForward, object: 1)
            }
        }
    }

    // Forward key events to next responder (MainViewController) for handling
    override func keyDown(with event: NSEvent) {
        nextResponder?.keyDown(with: event)
    }
}
