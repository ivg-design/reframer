import Cocoa
import AVFoundation
import CoreImage
import Combine

private struct FilterPipelineSnapshot: Sendable {
    let quickFilter: VideoFilter?
    let quickFilterValue: Double
    let advancedFilters: [VideoFilter]
    let settings: FilterSettings

    var isEmpty: Bool {
        quickFilter == nil && advancedFilters.isEmpty
    }
}

private final class FilterPipelineState: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = FilterPipelineSnapshot(
        quickFilter: nil,
        quickFilterValue: 0.5,
        advancedFilters: [],
        settings: .defaults
    )

    func update(_ value: FilterPipelineSnapshot) {
        lock.lock()
        snapshot = value
        lock.unlock()
    }

    func current() -> FilterPipelineSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

/// Immutable pointer-pan geometry, separated from AppKit event delivery so a
/// drag can be verified without synthesizing system input.
struct VideoPointerPanSession: Equatable {
    let startLocation: NSPoint
    let startOffset: CGSize

    func offset(at location: NSPoint) -> CGSize {
        CGSize(
            width: startOffset.width + location.x - startLocation.x,
            height: startOffset.height + location.y - startLocation.y
        )
    }
}

/// Pure AppKit video view with zoom, pan, and mouse handling
class VideoView: NSView {

    // MARK: - Properties

    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var currentAsset: AVAsset?
    private var timeObserver: Any?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerItemFailedObserver: NSObjectProtocol?
    private var playerItemEndedObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var loadToken = UUID()
    private var filterToken = UUID()
    private var failedLoadToken: UUID?
    private var frameTimeline: VideoFrameTimeline?
    private var frameSeekCoordinator = FrameSeekCoordinator()
    private var playerIsReady = false
    private var metadataIsReady = false
    private let filterPipelineState = FilterPipelineState()
    private var filterComposition: AVVideoComposition?
    private var filterBuildInProgress = false
    private var filterRefreshWorkItem: DispatchWorkItem?
    private var scrubWasPlaying = false

    // Core Image context for filter processing (reused for performance)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    // Pointer dragging always pans the loaded picture while unlocked.
    private var pointerPanSession: VideoPointerPanSession?
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

        Publishers.CombineLatest(state.$isLocked, state.$isVideoLoaded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked, isLoaded in
                guard let self else { return }
                if isLocked || !isLoaded {
                    self.pointerPanSession = nil
                }
                self.window?.invalidateCursorRects(for: self)
            }
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
                self?.applyPlaybackState(isPlaying: isPlaying)
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
                guard let self else { return }
                if let url {
                    self.loadVideo(url: url)
                } else {
                    self.cleanup()
                    state.isPlaying = false
                    state.isAtEnd = false
                    state.isVideoLoaded = false
                    state.isVideoLoading = false
                    state.videoErrorMessage = nil
                    state.filterErrorMessage = nil
                    state.currentTime = 0
                    state.currentFrame = 0
                    state.duration = 0
                    state.totalFrames = 0
                    state.videoNaturalSize = .zero
                }
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

        state.scrubRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                switch request {
                case .began:
                    self?.beginScrubbing()
                case .preview(let time):
                    self?.previewScrub(to: time)
                case .ended(let time):
                    self?.endScrubbing(at: time)
                }
            }
            .store(in: &cancellables)

        state.reloadRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak state] in
                guard let url = state?.videoURL else { return }
                self?.loadVideo(url: url)
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
        failedLoadToken = nil
        playerIsReady = false
        metadataIsReady = false

        state.isVideoLoaded = false
        state.isVideoLoading = true
        state.videoErrorMessage = nil
        state.filterErrorMessage = nil
        state.isAtEnd = false
        state.currentTime = 0
        state.currentFrame = 0
        state.duration = 0
        state.totalFrames = 0
        state.videoNaturalSize = .zero
        frameTimeline = nil
        frameSeekCoordinator.reset()

        loadTask = Task { [weak self, weak state] in
            guard let self else { return }
            do {
                let videoAsset = try await VideoFormats.preflight(url)
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.loadToken == token, let state else { return }
                    self.configurePlayer(asset: videoAsset, state: state, token: token)
                }
                try await self.loadMetadata(for: videoAsset, state: state, token: token)
                try Task.checkCancellation()
            } catch {
                guard !(error is CancellationError) else { return }
                await MainActor.run {
                    self.failLoad(error, token: token)
                }
            }
            await MainActor.run {
                if self.loadToken == token {
                    self.loadTask = nil
                }
            }
        }
    }

    private func configurePlayer(asset: AVURLAsset, state: VideoState, token: UUID) {
        guard loadToken == token else { return }
        currentAsset = asset
        let item = AVPlayerItem(asset: asset)
        playerItem = item
        player = AVPlayer(playerItem: item)
        player?.volume = state.volume
        playerLayer.player = player
        installPlayerStatusObserver(token: token)
        installPlayerItemObservers(token: token)
        installTimeObserver(token: token)
        applyCurrentFilters()
    }

    private func installPlayerStatusObserver(token: UUID) {
        playerTimeControlObservation = player?.observe(
            \.timeControlStatus,
            options: [.new]
        ) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self,
                      self.loadToken == token,
                      let state = self.videoState else { return }
                switch player.timeControlStatus {
                case .playing:
                    if !state.isPlaying {
                        state.isPlaying = true
                    }
                case .paused:
                    if state.isPlaying, player.rate == 0, !state.isScrubbing {
                        state.isPlaying = false
                    }
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func installPlayerItemObservers(token: UUID) {
        playerItemStatusObservation = playerItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self, self.videoState != nil else { return }
            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                switch item.status {
                case .readyToPlay:
                    self.playerIsReady = true
                    self.updateLoadReadiness(token: token)
                case .failed:
                    self.failLoad(
                        item.error ?? NSError(
                            domain: "Reframer.Playback",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "AVFoundation could not prepare this video."]
                        ),
                        token: token
                    )
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
                guard let self else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.failLoad(
                    error ?? NSError(
                        domain: "Reframer.Playback",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Playback stopped before the end of the video."]
                    ),
                    token: token
                )
            }

            playerItemEndedObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self,
                      self.loadToken == token,
                      let state = self.videoState else { return }
                state.isAtEnd = true
                state.isPlaying = false
                if let timeline = self.frameTimeline, !timeline.isEmpty {
                    state.currentFrame = timeline.count - 1
                }
                state.currentTime = state.duration
            }
        }
    }

    private func installTimeObserver(token: UUID) {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  self.loadToken == token,
                  let state = self.videoState else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite, !self.frameSeekCoordinator.hasPendingSeek {
                state.currentTime = sec
                if let timeline = self.frameTimeline {
                    state.currentFrame = timeline.frameIndex(containing: time)
                }
            }
        }
    }

    private func loadMetadata(for asset: AVAsset, state: VideoState?, token: UUID) async throws {
        let duration = try await asset.load(.duration)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoPreflightError.noVideoTrack
        }
        let nominalFrameRate = try await Double(track.load(.nominalFrameRate))
        let (naturalSize, preferredTransform) = try await track.load(.naturalSize, .preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let resolvedSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        let seconds = CMTimeGetSeconds(duration)
        guard duration.isValid,
              duration.isNumeric,
              seconds.isFinite,
              seconds > 0 else {
            throw VideoPreflightError.invalidDuration
        }
        guard resolvedSize.width.isFinite,
              resolvedSize.height.isFinite,
              resolvedSize.width > 0,
              resolvedSize.height > 0 else {
            throw VideoPreflightError.invalidVideoDimensions
        }
        let timeline = try await VideoFrameTimeline.load(
            asset: asset,
            track: track,
            nominalFrameRate: nominalFrameRate
        )

        await MainActor.run {
            guard let state, self.loadToken == token else { return }
            state.duration = seconds
            state.totalFrames = timeline.count
            if timeline.nominalFrameRate > 0 {
                state.frameRate = timeline.nominalFrameRate
            }
            state.videoNaturalSize = resolvedSize
            self.frameTimeline = timeline
            self.metadataIsReady = true
            self.updateLoadReadiness(token: token)
        }
    }

    func seek(to time: Double, accurate: Bool) {
        guard let state = videoState,
              let timeline = frameTimeline,
              state.isVideoLoaded,
              !timeline.isEmpty else { return }
        let clampedTime = max(0, min(state.duration, time))
        let requestedTime = CMTime(seconds: clampedTime, preferredTimescale: 60_000)
        let frame = timeline.nearestFrameIndex(to: requestedTime)
        state.isAtEnd = false

        if accurate {
            seekToFrame(frame)
            return
        }

        let target = frameSeekCoordinator.begin(frame: frame, timeline: timeline)
        guard let item = playerItem else { return }
        let tolerance = CMTime(seconds: 0.08, preferredTimescale: 60_000)
        player?.seek(
            to: requestedTime,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self, weak state, weak item] finished in
            DispatchQueue.main.async {
                guard let self,
                      let state,
                      let item,
                      item === self.playerItem,
                      self.frameSeekCoordinator.desiredTarget == target else { return }
                self.frameSeekCoordinator.complete(target)
                let actualTime = self.player?.currentTime() ?? requestedTime
                let actualSeconds = CMTimeGetSeconds(actualTime)
                state.currentTime = actualSeconds.isFinite ? max(0, actualSeconds) : clampedTime
                state.currentFrame = timeline.frameIndex(containing: actualTime)
                if !finished {
                    state.isAtEnd = false
                }
            }
        }
        state.currentTime = clampedTime
        state.currentFrame = frame
    }

    func seekToFrame(_ frame: Int) {
        guard let timeline = frameTimeline, !timeline.isEmpty else { return }
        let target = frameSeekCoordinator.begin(frame: frame, timeline: timeline)
        performExactSeek(to: target, timeline: timeline, resumePlayback: false)
    }

    private func beginScrubbing() {
        guard let state = videoState, state.isVideoLoaded else { return }
        scrubWasPlaying = state.isPlaying || player?.timeControlStatus == .playing
        player?.pause()
        state.isPlaying = false
        frameSeekCoordinator.reset()
    }

    private func previewScrub(to time: Double) {
        guard let state = videoState,
              let timeline = frameTimeline,
              state.isVideoLoaded,
              !timeline.isEmpty else { return }

        let clampedTime = max(0, min(state.duration, time))
        let requestedTime = CMTime(seconds: clampedTime, preferredTimescale: 60_000)
        let frame = timeline.nearestFrameIndex(to: requestedTime)
        let target = frameSeekCoordinator.begin(frame: frame, timeline: timeline)
        guard let item = playerItem else { return }
        let tolerance = CMTime(seconds: 0.08, preferredTimescale: 60_000)

        player?.seek(
            to: requestedTime,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self, weak state, weak item] finished in
            DispatchQueue.main.async {
                guard let self,
                      let state,
                      let item,
                      item === self.playerItem,
                      self.frameSeekCoordinator.desiredTarget == target else { return }
                self.frameSeekCoordinator.complete(target)
                guard finished else { return }
                let actualTime = self.player?.currentTime() ?? requestedTime
                let seconds = CMTimeGetSeconds(actualTime)
                state.currentTime = seconds.isFinite ? max(0, seconds) : clampedTime
                state.currentFrame = timeline.frameIndex(containing: actualTime)
                state.isAtEnd = false
            }
        }

        state.currentTime = clampedTime
        state.currentFrame = frame
    }

    private func endScrubbing(at time: Double) {
        guard let state = videoState,
              let timeline = frameTimeline,
              state.isVideoLoaded,
              !timeline.isEmpty else {
            scrubWasPlaying = false
            return
        }

        let clampedTime = max(0, min(state.duration, time))
        let frame = timeline.nearestFrameIndex(
            to: CMTime(seconds: clampedTime, preferredTimescale: 60_000)
        )
        let shouldResume = scrubWasPlaying
        scrubWasPlaying = false
        let target = frameSeekCoordinator.begin(frame: frame, timeline: timeline)
        performExactSeek(to: target, timeline: timeline, resumePlayback: shouldResume)
    }

    func stepFrame(forward: Bool, amount: Int) {
        guard let state = videoState,
              let timeline = frameTimeline,
              state.isVideoLoaded,
              !timeline.isEmpty else { return }
        player?.pause()
        state.isPlaying = false
        state.isAtEnd = false

        let magnitude = max(1, amount)
        let target = frameSeekCoordinator.target(
            from: state.currentFrame,
            delta: forward ? magnitude : -magnitude,
            timeline: timeline
        )
        performExactSeek(to: target, timeline: timeline, resumePlayback: false)
    }

    private func performExactSeek(
        to seekTarget: FrameSeekTarget,
        timeline: VideoFrameTimeline,
        resumePlayback: Bool
    ) {
        guard let state = videoState,
              let item = playerItem else { return }
        let target = timeline.clampedIndex(seekTarget.frame)
        let time = timeline.time(forFrame: target)
        let generation = loadToken
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self, weak state, weak item] finished in
            DispatchQueue.main.async {
                guard let self,
                      self.loadToken == generation,
                      let state,
                      let item,
                      item === self.playerItem,
                      self.frameSeekCoordinator.desiredTarget == seekTarget else { return }
                self.frameSeekCoordinator.complete(seekTarget)
                if finished {
                    let shouldResume = resumePlayback && (state.isPlaying || !state.isAtEnd)
                    state.currentFrame = target
                    state.currentTime = max(0, CMTimeGetSeconds(time))
                    state.isAtEnd = false
                    if shouldResume {
                        self.player?.play()
                    }
                } else {
                    let actualTime = self.player?.currentTime() ?? .zero
                    let actualSeconds = CMTimeGetSeconds(actualTime)
                    state.currentFrame = timeline.frameIndex(containing: actualTime)
                    state.currentTime = actualSeconds.isFinite ? max(0, actualSeconds) : 0
                }
            }
        }
        state.currentFrame = target
        state.currentTime = max(0, CMTimeGetSeconds(time))
    }

    private func applyPlaybackState(isPlaying: Bool) {
        guard let state = videoState else { return }
        guard isPlaying else {
            player?.pause()
            return
        }
        guard state.isVideoLoaded else {
            player?.pause()
            return
        }
        if state.isAtEnd, let timeline = frameTimeline, !timeline.isEmpty {
            let target = frameSeekCoordinator.begin(frame: 0, timeline: timeline)
            performExactSeek(to: target, timeline: timeline, resumePlayback: true)
        } else {
            player?.play()
        }
    }

    private func updateLoadReadiness(token: UUID) {
        guard loadToken == token,
              failedLoadToken != token,
              playerIsReady,
              metadataIsReady,
              let state = videoState else { return }
        state.isVideoLoading = false
        state.isVideoLoaded = true
        state.videoErrorMessage = nil
        if state.isPlaying {
            player?.play()
        }
    }

    private func failLoad(_ error: Error, token: UUID) {
        guard loadToken == token, failedLoadToken != token else { return }
        failedLoadToken = token
        player?.pause()
        videoState?.isPlaying = false
        videoState?.isVideoLoading = false
        videoState?.isVideoLoaded = false
        videoState?.isAtEnd = false
        videoState?.videoErrorMessage = error.localizedDescription
    }

    private func cleanup() {
        loadTask?.cancel()
        loadTask = nil
        loadToken = UUID()
        filterToken = UUID()
        frameSeekCoordinator.reset()
        frameTimeline = nil
        playerIsReady = false
        metadataIsReady = false
        scrubWasPlaying = false
        filterRefreshWorkItem?.cancel()
        filterRefreshWorkItem = nil
        filterComposition = nil
        filterBuildInProgress = false
        filterPipelineState.update(
            FilterPipelineSnapshot(
                quickFilter: nil,
                quickFilterValue: 0.5,
                advancedFilters: [],
                settings: .defaults
            )
        )
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        playerTimeControlObservation = nil
        playerItemStatusObservation = nil
        if let observer = playerItemFailedObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemFailedObserver = nil
        }
        if let observer = playerItemEndedObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemEndedObserver = nil
        }
        player?.pause()
        player = nil
        playerItem = nil
        currentAsset = nil
        playerLayer.player = nil
    }

    deinit {
        cleanup()
    }

    // MARK: - Video Filters

    private func applyCurrentFilters() {
        guard let asset = currentAsset,
              let state = videoState,
              let playerItem = playerItem else { return }

        let snapshot = FilterPipelineSnapshot(
            quickFilter: state.quickFilter,
            quickFilterValue: state.quickFilterValue,
            advancedFilters: state.orderedAdvancedFilters,
            settings: state.filterSettings.sanitized
        )
        filterPipelineState.update(snapshot)
        state.filterErrorMessage = nil

        // Invalidate pending asynchronous composition creation before clearing,
        // otherwise an older completion can silently resurrect the filter.
        guard !snapshot.isEmpty else {
            filterToken = UUID()
            filterBuildInProgress = false
            filterComposition = nil
            filterRefreshWorkItem?.cancel()
            filterRefreshWorkItem = nil
            playerItem.videoComposition = nil
            return
        }

        if let filterComposition {
            playerItem.videoComposition = filterComposition
            schedulePausedFilterRefresh()
            return
        }

        guard !filterBuildInProgress else { return }
        filterBuildInProgress = true
        let token = UUID()
        filterToken = token
        let generation = loadToken
        let pipelineState = filterPipelineState
        let context = ciContext

        AVVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                let currentSnapshot = pipelineState.current()
                guard !currentSnapshot.isEmpty else {
                    request.finish(with: request.sourceImage, context: context)
                    return
                }

                var currentImage = request.sourceImage
                var filters: [CIFilter] = []
                if let quickFilter = currentSnapshot.quickFilter,
                   let quick = quickFilter.createQuickFilter(
                    normalizedValue: currentSnapshot.quickFilterValue
                   ) {
                    filters.append(quick)
                }
                for filter in currentSnapshot.advancedFilters {
                    if let created = filter.createFilter(settings: currentSnapshot.settings) {
                        filters.append(created)
                    }
                }
                for filter in filters {
                    filter.setValue(currentImage, forKey: kCIInputImageKey)
                    if let outputImage = filter.outputImage {
                        currentImage = outputImage
                    }
                }

                let sourceExtent = request.sourceImage.extent
                let output = currentImage
                    .clamped(to: sourceExtent)
                    .cropped(to: sourceExtent)
                request.finish(with: output, context: context)
            },
            completionHandler: { [weak self, weak playerItem] composition, error in
                DispatchQueue.main.async {
                    guard let self,
                          self.loadToken == generation,
                          self.filterToken == token,
                          let playerItem,
                          playerItem === self.playerItem else { return }
                    self.filterBuildInProgress = false
                    if let composition {
                        self.filterComposition = composition
                        playerItem.videoComposition = composition
                        self.videoState?.filterErrorMessage = nil
                        self.schedulePausedFilterRefresh()
                    } else {
                        self.filterComposition = nil
                        playerItem.videoComposition = nil
                        self.videoState?.filterErrorMessage =
                            error?.localizedDescription
                            ?? "The selected filters could not be rendered."
                    }
                }
            }
        )
    }

    private func schedulePausedFilterRefresh() {
        guard videoState?.isPlaying != true else { return }
        filterRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.videoState?.isPlaying != true,
                  !self.frameSeekCoordinator.hasPendingSeek,
                  let player = self.player else { return }
            let time = player.currentTime()
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        filterRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    // MARK: - Mouse Handling

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        guard let state = videoState, state.isVideoLoaded, !state.isLocked else {
            return
        }
        addCursorRect(bounds, cursor: pointerPanSession == nil ? .openHand : .closedHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown,
              let state = videoState,
              state.isVideoLoaded,
              !state.isLocked else {
            super.mouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        pointerPanSession = VideoPointerPanSession(
            startLocation: convert(event.locationInWindow, from: nil),
            startOffset: state.panOffset
        )
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let state = videoState,
              state.isVideoLoaded,
              !state.isLocked,
              let pointerPanSession else {
            return
        }

        state.panOffset = pointerPanSession.offset(
            at: convert(event.locationInWindow, from: nil)
        )
    }

    override func mouseUp(with event: NSEvent) {
        pointerPanSession = nil
        window?.invalidateCursorRects(for: self)
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
