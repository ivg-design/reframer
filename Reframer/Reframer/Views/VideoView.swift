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
    private var currentAsset: AVAsset?
    private var currentVideoAsset: AVURLAsset?
    private var timeObserver: Any?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerItemFailedObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var loadToken = UUID()
    private var filterToken = UUID()

    // Core Image context for filter processing (reused for performance)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    // Drag state for Ctrl+drag panning
    private var dragStart: NSPoint = .zero
    private var panStart: CGSize = .zero
    private var isPanning: Bool = false  // Track if we started a pan operation
    private var scrollStepper = ScrollStepAccumulator()

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
                guard let self = self else { return }
                if isPlaying {
                    self.player?.play()
                } else {
                    self.player?.pause()
                }
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
                guard let self = self, let url = url else { return }
                self.loadVideo(url: url)
            }
            .store(in: &cancellables)

        state.seekRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                switch request {
                case .time(let time, let accurate):
                    self?.seek(to: time, accurate: accurate)
                case .frame(let frame):
                    self?.seekToFrame(frame)
                }
            }
            .store(in: &cancellables)

        state.frameStepRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                let forward = request.direction == .forward
                self?.stepFrame(forward: forward, amount: request.amount)
            }
            .store(in: &cancellables)

        // Observe quick filter changes
        state.$quickFilter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFilters() }
            .store(in: &cancellables)

        state.$quickFilterValue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFilters() }
            .store(in: &cancellables)

        // Observe advanced filter changes
        state.$advancedFilters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFilters() }
            .store(in: &cancellables)

        state.$filterSettings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFilters() }
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

        let token = UUID()
        loadToken = token
        filterToken = token

        // Reset state for new video
        state.isVideoLoaded = false
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        lastSeekTime = -1  // Allow scrubbing from the start

        let videoAsset = AVURLAsset(url: url)
        currentVideoAsset = videoAsset

        // Set up player SYNCHRONOUSLY for responsive scrubbing
        currentAsset = videoAsset
        playerItem = AVPlayerItem(asset: videoAsset)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = state.volume
        playerLayer.player = player
        installPlayerItemObservers(token: token)
        installTimeObserver()
        applyCurrentFilters()
        if state.isPlaying {
            player?.play()
        }

        // Load metadata asynchronously
        Task { [weak self, weak state] in
            guard let self = self else { return }
            do {
                try await self.loadMetadata(for: videoAsset, state: state, token: token)
            } catch {
                await MainActor.run {
                    self.showVideoLoadError(error)
                }
            }
        }
    }

    private var lastSeekTime: Double = -1

    private func installPlayerItemObservers(token: UUID) {
        playerItemStatusObservation = playerItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self, let state = self.videoState else { return }
            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                switch item.status {
                case .readyToPlay:
                    state.isVideoLoaded = true
                case .failed:
                    state.isVideoLoaded = false
                    self.showVideoLoadError(item.error ?? NSError(domain: "AVFoundation", code: -1))
                default:
                    break
                }
            }
        }

        if let observer = playerItemFailedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let item = playerItem {
            playerItemFailedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.videoState?.isVideoLoaded = false
                if let error = error {
                    self.showVideoLoadError(error)
                }
            }
        }
    }

    private func installTimeObserver() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
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

    private func loadMetadata(for asset: AVAsset, state: VideoState?, token: UUID) async throws {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)

        await MainActor.run {
            guard let state = state, self.loadToken == token else { return }
            state.duration = CMTimeGetSeconds(duration)
            state.totalFrames = Int(state.duration * state.frameRate)
        }

        if let track = tracks.first(where: { $0.mediaType == .video }) {
            var fps = try? await track.load(.nominalFrameRate)
            let (naturalSize, preferredTransform) = try await track.load(.naturalSize, .preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let resolvedSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

            if (fps == nil || fps == 0), let sourceTrack = try? await currentVideoAsset?.load(.tracks).first(where: { $0.mediaType == .video }) {
                fps = try? await sourceTrack.load(.nominalFrameRate)
            }

            await MainActor.run {
                guard let state = state, self.loadToken == token else { return }
                if let fps = fps, fps > 0 {
                    state.frameRate = Double(fps)
                    state.totalFrames = Int(state.duration * Double(fps))
                }
                state.videoNaturalSize = resolvedSize
            }
        }
    }

    func seek(to time: Double, accurate: Bool) {
        guard let state = videoState else { return }

        // Clamp to valid range
        let clampedTime = max(0, min(state.duration, time))

        // Avoid redundant seeks to the same time
        if abs(clampedTime - lastSeekTime) < 0.01 { return }
        lastSeekTime = clampedTime

        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player?.currentItem?.cancelPendingSeeks()

        // Always use accurate seeking for smooth scrubbing (seeks to exact frame, not keyframe)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        state.currentTime = clampedTime
        state.currentFrame = Int(clampedTime * state.frameRate)
    }

    func seekToFrame(_ frame: Int) {
        guard let state = videoState else { return }
        let time = Double(frame) / state.frameRate
        seek(to: time, accurate: true)
    }

    func stepFrame(forward: Bool, amount: Int) {
        guard let state = videoState else { return }
        player?.pause()
        state.isPlaying = false

        let delta = forward ? amount : -amount
        let newFrame = max(0, min(state.totalFrames - 1, state.currentFrame + delta))

        // Update frame immediately so rapid key presses use the correct frame
        state.currentFrame = newFrame
        state.currentTime = Double(newFrame) / state.frameRate

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
        playerItemStatusObservation = nil
        if let observer = playerItemFailedObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemFailedObserver = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
        currentAsset = nil
        currentVideoAsset = nil
    }

    deinit {
        cleanup()
    }

    // MARK: - Video Filters

    private func applyCurrentFilters() {
        guard let asset = currentAsset,
              let state = videoState,
              let playerItem = playerItem else { return }

        let quickFilter = state.quickFilter
        let quickFilterValue = state.quickFilterValue
        let orderedAdvanced = state.orderedAdvancedFilters
        let settings = state.filterSettings

        // If no filters active (neither quick nor advanced), remove any existing composition
        guard quickFilter != nil || !orderedAdvanced.isEmpty else {
            playerItem.videoComposition = nil
            return
        }

        let token = UUID()
        filterToken = token

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
                    guard self.filterToken == token else { return }
                    self.createVideoComposition(
                        for: playerItem,
                        renderSize: renderSize,
                        frameRate: nominalFrameRate,
                        quickFilter: quickFilter,
                        quickFilterValue: quickFilterValue,
                        advancedFilters: orderedAdvanced,
                        settings: settings
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
        quickFilter: VideoFilter?,
        quickFilterValue: Double,
        advancedFilters: [VideoFilter],
        settings: FilterSettings
    ) {
        let composition = AVMutableVideoComposition(asset: playerItem.asset, applyingCIFiltersWithHandler: { [weak self] request in
            guard let self = self else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            // Start with source image
            var currentImage = request.sourceImage

            // Chain all filters together (create per-frame to avoid thread-safety issues)
            var filters: [CIFilter] = []
            if let quickFilter = quickFilter,
               let quick = quickFilter.createQuickFilter(normalizedValue: quickFilterValue) {
                filters.append(quick)
            }
            for filter in advancedFilters {
                if let created = filter.createFilter(settings: settings) {
                    filters.append(created)
                }
            }
            for filter in filters {
                filter.setValue(currentImage, forKey: kCIInputImageKey)
                if let outputImage = filter.outputImage {
                    currentImage = outputImage
                }
            }

            // Clamp final output to prevent infinite extent issues
            let clampedImage = currentImage.clamped(to: request.sourceImage.extent)
            request.finish(with: clampedImage, context: self.ciContext)
        })

        composition.renderSize = renderSize

        // Set frame duration based on video frame rate
        let fps = frameRate > 0 ? Double(frameRate) : 30.0
        composition.frameDuration = CMTimeMakeWithSeconds(1.0 / fps, preferredTimescale: 600)

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

        let direction = delta > 0 ? 1.0 : -1.0
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
            let steps = scrollStepper.steps(for: delta, hasPreciseDeltas: event.hasPreciseScrollingDeltas)
            for step in steps {
                state.requestFrameStep(direction: step, amount: 1)
            }
        }
    }

    // Forward key events to next responder (MainViewController) for handling
    override func keyDown(with event: NSEvent) {
        nextResponder?.keyDown(with: event)
    }
}
