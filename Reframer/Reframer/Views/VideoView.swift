import Cocoa
import AVFoundation
import CoreImage
import Combine

struct SecurityScopedURLAccess: @unchecked Sendable {
    let start: @Sendable (URL) -> Bool
    let stop: @Sendable (URL) -> Void

    static let live = SecurityScopedURLAccess(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

/// One balanced security-scope acquisition shared by every asynchronous
/// operation belonging to a single video load. ARC is the reference count:
/// access ends only after the view and all in-flight callbacks release it.
final class SecurityScopedURLLease: @unchecked Sendable {
    let url: URL
    private let stop: @Sendable (URL) -> Void
    private let didStart: Bool

    init(url: URL, access: SecurityScopedURLAccess = .live) {
        self.url = url
        stop = access.stop
        didStart = access.start(url)
    }

    deinit {
        if didStart {
            stop(url)
        }
    }
}

struct VideoLoadEnvironment: @unchecked Sendable {
    typealias Preflight = @Sendable (URL) async throws -> AVURLAsset
    typealias TimelineLoader = @Sendable (
        AVAsset,
        AVAssetTrack,
        Double
    ) async throws -> VideoFrameTimeline

    let securityScopedAccess: SecurityScopedURLAccess
    let preflight: Preflight
    let loadTimeline: TimelineLoader

    static let live = VideoLoadEnvironment(
        securityScopedAccess: .live,
        preflight: { try await VideoFormats.preflight($0) },
        loadTimeline: { asset, track, nominalFrameRate in
            try await VideoFrameTimeline.load(
                asset: asset,
                track: track,
                nominalFrameRate: nominalFrameRate
            )
        }
    )
}

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

enum PlaybackStatusReconciliation {
    static func intent(
        currentIntent: Bool,
        status: AVPlayer.TimeControlStatus,
        rate: Float,
        isScrubbing: Bool,
        protectsPausedIntent: Bool
    ) -> Bool {
        if status == .paused,
           currentIntent,
           rate == 0,
           !isScrubbing,
           !protectsPausedIntent {
            return false
        }
        return currentIntent
    }
}

enum PlaybackResumeAuthorization {
    static func permits(
        capturedRevision: UInt64?,
        currentRevision: UInt64,
        isPlaying: Bool
    ) -> Bool {
        guard let capturedRevision else { return false }
        return isPlaying && capturedRevision == currentRevision
    }
}

enum PlaybackTransportAuthorization {
    static func permitsPlaying(
        currentIntent: Bool,
        isScrubbing: Bool,
        hasPendingPlaybackSeek: Bool
    ) -> Bool {
        currentIntent && !isScrubbing && !hasPendingPlaybackSeek
    }
}

/// A revision- and generation-scoped grace period for AVPlayer's transient
/// `.paused` callback immediately after `play()`. Generations prevent an old
/// timeout from cancelling a newer start that happens to share the same
/// playback-intent revision (for example, scrub pause/resume).
struct PlaybackStartGate {
    struct Token: Equatable {
        let intentRevision: UInt64
        let generation: UInt64
    }

    private(set) var token: Token?
    private var nextGeneration: UInt64 = 0

    mutating func begin(intentRevision: UInt64) -> Token {
        nextGeneration &+= 1
        let token = Token(
            intentRevision: intentRevision,
            generation: nextGeneration
        )
        self.token = token
        return token
    }

    func protectsPausedIntent(intentRevision: UInt64) -> Bool {
        token?.intentRevision == intentRevision
    }

    @discardableResult
    mutating func settle(_ expectedToken: Token) -> Bool {
        guard token == expectedToken else { return false }
        token = nil
        return true
    }

    @discardableResult
    mutating func expire(_ expectedToken: Token) -> Bool {
        settle(expectedToken)
    }

    mutating func cancel() {
        token = nil
        nextGeneration &+= 1
    }

    static func shouldClearIntentOnExpiry(
        status: AVPlayer.TimeControlStatus,
        rate: Float,
        isScrubbing: Bool,
        hasPendingPlaybackSeek: Bool
    ) -> Bool {
        status == .paused
            && rate == 0
            && !isScrubbing
            && !hasPendingPlaybackSeek
    }
}

/// Pure AppKit video view with zoom, pan, and mouse handling
class VideoView: NSView {

    // MARK: - Properties

    private static let playbackStartGraceInterval: TimeInterval = 2
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var currentAsset: AVAsset?
    private var playbackStartGate = PlaybackStartGate()
    private var playbackStartTimeoutWorkItem: DispatchWorkItem?
    private var timeObserver: Any?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var loadTask: Task<Void, Never>?
    private var activeResourceLease: SecurityScopedURLLease?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerItemFailedObserver: NSObjectProtocol?
    private var playerItemEndedObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var selectedVideoTrackID: CMPersistentTrackID?
    private var loadToken = UUID()
    private var filterToken = UUID()
    private var failedLoadToken: UUID?
    private var frameTimeline: VideoFrameTimeline?
    private var frameSeekCoordinator = FrameSeekCoordinator()
    private var previewSeekCoordinator = PreviewSeekCoordinator()
    private var timeSeekToken = UUID()
    private var timeSeekInFlightToken: UUID?
    private var timeSeekResumeIntentRevision: UInt64?
    private var playerIsReady = false
    private var metadataIsReady = false
    private let filterPipelineState = FilterPipelineState()
    private var filterComposition: AVVideoComposition?
    private var filterBuildInProgress = false
    private var filterRefreshWorkItem: DispatchWorkItem?
    private var filterRefreshCoordinator = DeferredRefreshCoordinator()

    /// Internal dependency seam used by deterministic lifecycle tests.
    var loadEnvironment: VideoLoadEnvironment = .live

    var hasActivePlaybackResources: Bool {
        player != nil
            || playerItem != nil
            || currentAsset != nil
            || playerLayer.player != nil
    }

    /// Internal observability for deterministic tests of asynchronous resume
    /// authorization. This reports logical completion, not merely a fixed
    /// elapsed delay.
    var hasPendingPlaybackSeek: Bool {
        frameSeekCoordinator.hasPendingSeek
            || timeSeekInFlightToken != nil
    }

    /// Internal lifecycle-test visibility for the physical AVPlayer transport.
    var isPlaybackTransportActive: Bool {
        guard let player else { return false }
        return player.rate != 0 || player.timeControlStatus == .playing
    }

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
                    self.cancelPointerPan()
                }
                self.window?.invalidateCursorRects(for: self)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cancelPointerPan() }
            .store(in: &cancellables)

        // Observe video size changes
        state.$videoNaturalSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTransform() }
            .store(in: &cancellables)

        // Observe playback state
        state.$isPlaying
            .sink { [weak self] isPlaying in
                precondition(Thread.isMainThread)
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
            .sink { [weak self] request in
                precondition(Thread.isMainThread)
                switch request {
                case .began:
                    self?.beginScrubbing()
                case .preview(let time):
                    self?.previewScrub(to: time)
                case .ended(let time):
                    self?.endScrubbing(at: time)
                case .cancelled:
                    self?.cancelScrubSession()
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
        guard let state = videoState else { return }
        let environment = loadEnvironment
        // Nested starts are supported. Acquiring first prevents a permission
        // gap while the prior player graph is being dismantled.
        let lease = SecurityScopedURLLease(
            url: url,
            access: environment.securityScopedAccess
        )
        state.cancelScrubbing()
        state.setPlaybackIntent(false)
        cleanup()
        activeResourceLease = lease

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
        state.frameNavigationPrecision = .unavailable
        state.frameNavigationMessage = nil
        state.videoNaturalSize = .zero
        frameTimeline = nil
        frameSeekCoordinator.reset()
        previewSeekCoordinator.cancel()

        loadTask = Task { [weak self, weak state, lease, environment] in
            defer { withExtendedLifetime(lease) {} }
            guard let self else { return }
            do {
                let videoAsset = try await environment.preflight(url)
                try Task.checkCancellation()
                let selectedTrack = try await VideoFormats.selectVideoTrack(
                    in: videoAsset
                )
                try Task.checkCancellation()
                let playbackAsset = try await VideoFormats.preparePlaybackAsset(
                    from: videoAsset,
                    selectedVideoTrack: selectedTrack
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.loadToken == token, let state else { return }
                    self.configurePlayer(
                        asset: playbackAsset.asset,
                        selectedTrackID: playbackAsset.selectedVideoTrackID,
                        state: state,
                        token: token
                    )
                }
                try await self.loadMetadata(
                    for: playbackAsset.asset,
                    selectedTrack: selectedTrack,
                    state: state,
                    token: token,
                    timelineLoader: environment.loadTimeline
                )
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

    private func configurePlayer(
        asset: AVAsset,
        selectedTrackID: CMPersistentTrackID,
        state: VideoState,
        token: UUID
    ) {
        guard loadToken == token else { return }
        currentAsset = asset
        self.selectedVideoTrackID = selectedTrackID
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
                let status = player.timeControlStatus
                let reconciledIntent = PlaybackStatusReconciliation.intent(
                    currentIntent: state.isPlaying,
                    status: status,
                    rate: player.rate,
                    isScrubbing: state.isScrubbing,
                    protectsPausedIntent: self.protectsPausedIntent(for: state)
                )
                switch status {
                case .playing:
                    let permitsTransport =
                        PlaybackTransportAuthorization.permitsPlaying(
                            currentIntent: reconciledIntent,
                            isScrubbing: state.isScrubbing,
                            hasPendingPlaybackSeek:
                                self.hasPendingPlaybackSeek
                        )
                    self.cancelPlaybackStart()
                    // VideoState is the playback intent authority. AVPlayer
                    // can deliver a stale `.playing` transition after a rapid
                    // play-then-pause command or while a scrub/seek owns the
                    // transport; never let that restart physical playback.
                    if !permitsTransport {
                        player.pause()
                    }
                case .paused:
                    if reconciledIntent != state.isPlaying {
                        state.setPlaybackIntent(reconciledIntent)
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
                    self.alignVideoTrackSelection(for: item)
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
                state.setPlaybackIntent(false)
                if let timeline = self.frameTimeline, !timeline.isEmpty {
                    state.currentFrame = timeline.count - 1
                }
                state.currentTime = state.duration
            }
        }
    }

    private func alignVideoTrackSelection(for item: AVPlayerItem) {
        guard let selectedVideoTrackID else { return }
        let videoTracks = item.tracks.filter {
            $0.assetTrack?.mediaType == .video
        }
        guard videoTracks.contains(where: {
            $0.assetTrack?.trackID == selectedVideoTrackID
        }) else { return }

        for itemTrack in videoTracks {
            itemTrack.isEnabled =
                itemTrack.assetTrack?.trackID == selectedVideoTrackID
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
            if sec.isFinite,
               !state.isScrubbing,
               !self.frameSeekCoordinator.hasPendingSeek,
               !self.previewSeekCoordinator.hasPendingSeek,
               self.timeSeekInFlightToken == nil {
                state.currentTime = sec
                if let timeline = self.frameTimeline {
                    state.currentFrame = timeline.frameIndex(containing: time)
                }
            }
        }
    }

    private func loadMetadata(
        for asset: AVAsset,
        selectedTrack: SelectedVideoTrack,
        state: VideoState?,
        token: UUID,
        timelineLoader: VideoLoadEnvironment.TimelineLoader
    ) async throws {
        let duration = try await asset.load(.duration)
        let track = selectedTrack.track
        let nominalFrameRate = selectedTrack.nominalFrameRate
        let resolvedSize = selectedTrack.displaySize
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
        let estimatedTimeline = VideoFrameTimeline.estimated(
            duration: duration,
            nominalFrameRate: nominalFrameRate
        )

        await MainActor.run {
            guard let state, self.loadToken == token else { return }
            state.duration = seconds
            state.totalFrames = estimatedTimeline?.count ?? 0
            if let estimatedTimeline, estimatedTimeline.nominalFrameRate > 0 {
                state.frameRate = estimatedTimeline.nominalFrameRate
            } else if nominalFrameRate.isFinite, nominalFrameRate > 0 {
                state.frameRate = nominalFrameRate
            }
            state.videoNaturalSize = resolvedSize
            self.frameTimeline = estimatedTimeline
            state.frameNavigationPrecision = .whileBuildingExactIndex(
                hasEstimatedTimeline: estimatedTimeline != nil
            )
            state.frameNavigationMessage = estimatedTimeline == nil
                ? "Frame navigation is unavailable for this video; time-based playback remains available."
                : "Exact frame boundaries are still being indexed. Frame numbers are temporarily estimated."
            self.metadataIsReady = true
            self.updateLoadReadiness(token: token)
        }

        try Task.checkCancellation()
        do {
            let timeline = try await timelineLoader(asset, track, nominalFrameRate)
            try Task.checkCancellation()
            await MainActor.run {
                guard let state, self.loadToken == token else { return }
                let promotedTarget = self.frameSeekCoordinator.promote(to: timeline)
                self.frameTimeline = timeline
                state.totalFrames = timeline.count
                if timeline.nominalFrameRate > 0 {
                    state.frameRate = timeline.nominalFrameRate
                }
                state.frameNavigationPrecision = .exact
                state.frameNavigationMessage = nil
                if let promotedTarget {
                    self.performExactSeek(to: promotedTarget, timeline: timeline)
                } else {
                    let currentTime = self.player?.currentTime() ?? .zero
                    state.currentFrame = timeline.frameIndex(containing: currentTime)
                    self.retryPausedFilterRefreshIfNeeded()
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await MainActor.run {
                guard let state, self.loadToken == token else { return }
                let hasEstimatedTimeline = self.frameTimeline != nil
                state.frameNavigationPrecision = .afterExactIndexFailure(
                    hasEstimatedTimeline: hasEstimatedTimeline
                )
                if hasEstimatedTimeline {
                    state.frameNavigationMessage =
                        "Exact frame indexing is unavailable for this video. Frame numbers use a \(NumericTextInput.canonical(state.frameRate, fractionDigits: 3)) fps estimate; playback remains available."
                } else {
                    state.frameNavigationMessage =
                        "Frame navigation is unavailable for this video; time-based playback remains available."
                }
            }
        }
    }

    func seek(to time: Double, accurate: Bool) {
        guard let state = videoState,
              state.isVideoLoaded,
              time.isFinite else { return }
        let clampedTime = max(0, min(state.duration, time))
        let requestedTime = CMTime(seconds: clampedTime, preferredTimescale: 60_000)
        let resumeIntentRevision = state.isPlaying
            ? state.playbackIntentRevision
            : nil

        if accurate, let timeline = frameTimeline, !timeline.isEmpty {
            let frame = timeline.nearestFrameIndex(to: requestedTime)
            let target = frameSeekCoordinator.begin(
                frame: frame,
                timeline: timeline,
                resumeIntentRevision: resumeIntentRevision
            )
            performExactSeek(to: target, timeline: timeline)
        } else {
            performTimeSeek(
                to: clampedTime,
                accurate: accurate,
                resumeIntentRevision: resumeIntentRevision
            )
        }
    }

    func seekToFrame(_ frame: Int) {
        guard let state = videoState,
              let timeline = frameTimeline,
              !timeline.isEmpty else { return }
        let target = frameSeekCoordinator.begin(
            frame: frame,
            timeline: timeline,
            resumeIntentRevision: state.isPlaying
                ? state.playbackIntentRevision
                : nil
        )
        performExactSeek(to: target, timeline: timeline)
    }

    private func beginScrubbing() {
        guard let state = videoState, state.isVideoLoaded else { return }
        cancelPlaybackStart()
        player?.pause()
        frameSeekCoordinator.reset()
        previewSeekCoordinator.cancel()
        timeSeekToken = UUID()
        timeSeekInFlightToken = nil
        timeSeekResumeIntentRevision = nil
    }

    private func previewScrub(to time: Double) {
        guard let state = videoState,
              state.isVideoLoaded,
              time.isFinite else { return }

        let clampedTime = max(0, min(state.duration, time))
        let requestedTime = CMTime(seconds: clampedTime, preferredTimescale: 60_000)
        state.currentTime = clampedTime
        if let timeline = frameTimeline, !timeline.isEmpty {
            state.currentFrame = timeline.nearestFrameIndex(to: requestedTime)
        }
        state.isAtEnd = false

        if case .start(let target) = previewSeekCoordinator.submit(time: clampedTime) {
            performPreviewSeek(target)
        }
    }

    private func endScrubbing(at time: Double) {
        previewSeekCoordinator.cancel()
        guard let state = videoState,
              state.isVideoLoaded,
              time.isFinite else {
            retryPausedFilterRefreshIfNeeded()
            return
        }

        let clampedTime = max(0, min(state.duration, time))
        let resumeIntentRevision = state.isPlaying
            ? state.playbackIntentRevision
            : nil
        if let timeline = frameTimeline, !timeline.isEmpty {
            let frame = timeline.nearestFrameIndex(
                to: CMTime(seconds: clampedTime, preferredTimescale: 60_000)
            )
            let target = frameSeekCoordinator.begin(
                frame: frame,
                timeline: timeline,
                resumeIntentRevision: resumeIntentRevision
            )
            performExactSeek(to: target, timeline: timeline)
        } else {
            performTimeSeek(
                to: clampedTime,
                accurate: true,
                resumeIntentRevision: resumeIntentRevision
            )
        }
    }

    private func cancelScrubSession() {
        previewSeekCoordinator.cancel()
        frameSeekCoordinator.reset()
        timeSeekToken = UUID()
        timeSeekInFlightToken = nil
        timeSeekResumeIntentRevision = nil
        retryPausedFilterRefreshIfNeeded()
    }

    private func performPreviewSeek(_ target: PreviewSeekTarget) {
        guard let state = videoState,
              state.isVideoLoaded,
              let item = playerItem,
              let resourceLease = activeResourceLease else {
            previewSeekCoordinator.cancel()
            return
        }

        let requestedTime = CMTime(
            seconds: target.time,
            preferredTimescale: 60_000
        )
        let tolerance = CMTime(seconds: 0.08, preferredTimescale: 60_000)
        let generation = loadToken
        player?.seek(
            to: requestedTime,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self, weak state, weak item, resourceLease] finished in
            DispatchQueue.main.async {
                defer { withExtendedLifetime(resourceLease) {} }
                guard let self,
                      self.loadToken == generation,
                      let state,
                      let item,
                      item === self.playerItem,
                      self.previewSeekCoordinator.inFlight == target else { return }

                if let next = self.previewSeekCoordinator.complete(target) {
                    self.performPreviewSeek(next)
                    return
                }

                if finished {
                    let actualTime = self.player?.currentTime() ?? requestedTime
                    let seconds = CMTimeGetSeconds(actualTime)
                    state.currentTime = seconds.isFinite ? max(0, seconds) : target.time
                    if let timeline = self.frameTimeline, !timeline.isEmpty {
                        state.currentFrame = timeline.frameIndex(containing: actualTime)
                    }
                }
                state.isAtEnd = false
                self.retryPausedFilterRefreshIfNeeded()
            }
        }
    }

    func stepFrame(forward: Bool, amount: Int) {
        guard let state = videoState,
              let timeline = frameTimeline,
              state.isVideoLoaded,
              !timeline.isEmpty else { return }
        player?.pause()
        state.setPlaybackIntent(false)
        state.isAtEnd = false

        let magnitude = max(1, amount)
        let target = frameSeekCoordinator.target(
            from: state.currentFrame,
            delta: forward ? magnitude : -magnitude,
            timeline: timeline
        )
        performExactSeek(to: target, timeline: timeline)
    }

    private func performExactSeek(
        to seekTarget: FrameSeekTarget,
        timeline: VideoFrameTimeline
    ) {
        guard let state = videoState,
              let item = playerItem,
              let player,
              let resourceLease = activeResourceLease else { return }
        if PlaybackResumeAuthorization.permits(
            capturedRevision: seekTarget.resumeIntentRevision,
            currentRevision: state.playbackIntentRevision,
            isPlaying: state.isPlaying
        ) {
            cancelPlaybackStart()
        }
        previewSeekCoordinator.cancel()
        timeSeekToken = UUID()
        timeSeekInFlightToken = nil
        timeSeekResumeIntentRevision = nil
        state.isAtEnd = false
        let target = timeline.clampedIndex(seekTarget.frame)
        let time = seekTarget.requestedTime
        let generation = loadToken
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self, weak state, weak item, resourceLease] finished in
            DispatchQueue.main.async {
                defer { withExtendedLifetime(resourceLease) {} }
                guard let self,
                      self.loadToken == generation,
                      let state,
                      let item,
                      item === self.playerItem,
                      let completedTarget =
                          self.frameSeekCoordinator.complete(seekTarget) else {
                    return
                }
                var didResumePlayback = false
                if finished {
                    state.currentFrame = target
                    state.currentTime = max(0, CMTimeGetSeconds(time))
                    state.isAtEnd = false
                    if PlaybackResumeAuthorization.permits(
                        capturedRevision:
                            completedTarget.resumeIntentRevision,
                        currentRevision: state.playbackIntentRevision,
                        isPlaying: state.isPlaying
                    ), let resumeIntentRevision =
                        completedTarget.resumeIntentRevision {
                        didResumePlayback = self.startPlayerPlayback(
                            intentRevision: resumeIntentRevision
                        )
                    }
                } else {
                    let actualTime = self.player?.currentTime() ?? .zero
                    let actualSeconds = CMTimeGetSeconds(actualTime)
                    state.currentFrame = timeline.frameIndex(containing: actualTime)
                    state.currentTime = actualSeconds.isFinite ? max(0, actualSeconds) : 0
                    if PlaybackResumeAuthorization.permits(
                        capturedRevision:
                            completedTarget.resumeIntentRevision,
                        currentRevision: state.playbackIntentRevision,
                        isPlaying: state.isPlaying
                    ) {
                        state.setPlaybackIntent(false)
                    }
                }
                if !didResumePlayback {
                    self.retryPausedFilterRefreshIfNeeded()
                }
            }
        }
        state.currentFrame = target
        state.currentTime = max(0, CMTimeGetSeconds(time))
    }

    private func performTimeSeek(
        to seconds: Double,
        accurate: Bool,
        resumeIntentRevision: UInt64?
    ) {
        guard let state = videoState,
              state.isVideoLoaded,
              seconds.isFinite,
              let item = playerItem,
              let resourceLease = activeResourceLease else { return }

        if PlaybackResumeAuthorization.permits(
            capturedRevision: resumeIntentRevision,
            currentRevision: state.playbackIntentRevision,
            isPlaying: state.isPlaying
        ) {
            cancelPlaybackStart()
        }
        previewSeekCoordinator.cancel()
        frameSeekCoordinator.reset()
        state.isAtEnd = false
        let token = UUID()
        timeSeekToken = token
        timeSeekInFlightToken = token
        timeSeekResumeIntentRevision = resumeIntentRevision
        let generation = loadToken
        let clampedTime = max(0, min(state.duration, seconds))
        let requestedTime = CMTime(seconds: clampedTime, preferredTimescale: 60_000)
        let tolerance = accurate
            ? CMTime.zero
            : CMTime(seconds: 0.08, preferredTimescale: 60_000)

        player?.seek(
            to: requestedTime,
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self, weak state, weak item, resourceLease] finished in
            DispatchQueue.main.async {
                defer { withExtendedLifetime(resourceLease) {} }
                guard let self,
                      self.loadToken == generation,
                      self.timeSeekToken == token,
                      let state,
                      let item,
                      item === self.playerItem else { return }
                let completedResumeIntentRevision =
                    self.timeSeekResumeIntentRevision
                self.timeSeekInFlightToken = nil
                self.timeSeekResumeIntentRevision = nil
                let actualTime = self.player?.currentTime() ?? requestedTime
                let actualSeconds = CMTimeGetSeconds(actualTime)
                state.currentTime = actualSeconds.isFinite ? max(0, actualSeconds) : clampedTime
                if let timeline = self.frameTimeline, !timeline.isEmpty {
                    state.currentFrame = timeline.frameIndex(containing: actualTime)
                }
                state.isAtEnd = false
                var didResumePlayback = false
                if finished,
                   PlaybackResumeAuthorization.permits(
                       capturedRevision:
                           completedResumeIntentRevision,
                       currentRevision: state.playbackIntentRevision,
                       isPlaying: state.isPlaying
                   ),
                   let resumeIntentRevision =
                       completedResumeIntentRevision {
                    didResumePlayback = self.startPlayerPlayback(
                        intentRevision: resumeIntentRevision
                    )
                } else if !finished,
                          PlaybackResumeAuthorization.permits(
                              capturedRevision:
                                  completedResumeIntentRevision,
                              currentRevision: state.playbackIntentRevision,
                              isPlaying: state.isPlaying
                          ) {
                    state.setPlaybackIntent(false)
                }
                if !didResumePlayback {
                    self.retryPausedFilterRefreshIfNeeded()
                }
            }
        }

        state.currentTime = clampedTime
        if let timeline = frameTimeline, !timeline.isEmpty {
            state.currentFrame = timeline.nearestFrameIndex(to: requestedTime)
        }
    }

    private func protectsPausedIntent(for state: VideoState) -> Bool {
        if playbackStartGate.protectsPausedIntent(
            intentRevision: state.playbackIntentRevision
        ) {
            return true
        }
        if PlaybackResumeAuthorization.permits(
            capturedRevision:
                frameSeekCoordinator.desiredTarget?.resumeIntentRevision,
            currentRevision: state.playbackIntentRevision,
            isPlaying: state.isPlaying
        ) {
            return true
        }
        return timeSeekInFlightToken != nil
            && PlaybackResumeAuthorization.permits(
                capturedRevision: timeSeekResumeIntentRevision,
                currentRevision: state.playbackIntentRevision,
                isPlaying: state.isPlaying
            )
    }

    @discardableResult
    private func startPlayerPlayback(
        intentRevision: UInt64,
        publishedIntent: Bool? = nil
    ) -> Bool {
        guard let state = videoState,
              let player,
              state.isVideoLoaded,
              !state.isScrubbing,
              PlaybackResumeAuthorization.permits(
                  capturedRevision: intentRevision,
                  currentRevision: state.playbackIntentRevision,
                  // `@Published` emits from willSet, so the synchronous sink
                  // supplies its new value until the stored property catches
                  // up at the end of the setter.
                  isPlaying: publishedIntent ?? state.isPlaying
              ) else {
            return false
        }

        playbackStartTimeoutWorkItem?.cancel()
        let startToken = playbackStartGate.begin(
            intentRevision: intentRevision
        )
        let loadGeneration = loadToken
        let workItem = DispatchWorkItem {
            [weak self, weak state, weak player] in
            guard let self,
                  let state,
                  let player,
                  self.loadToken == loadGeneration,
                  player === self.player,
                  PlaybackResumeAuthorization.permits(
                      capturedRevision: startToken.intentRevision,
                      currentRevision: state.playbackIntentRevision,
                      isPlaying: state.isPlaying
                  ),
                  self.playbackStartGate.expire(startToken) else {
                return
            }
            self.playbackStartTimeoutWorkItem = nil
            if PlaybackStartGate.shouldClearIntentOnExpiry(
                status: player.timeControlStatus,
                rate: player.rate,
                isScrubbing: state.isScrubbing,
                hasPendingPlaybackSeek: self.hasPendingPlaybackSeek
            ) {
                state.setPlaybackIntent(false)
            }
        }
        playbackStartTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.playbackStartGraceInterval,
            execute: workItem
        )
        player.play()
        return true
    }

    private func cancelPlaybackStart() {
        playbackStartTimeoutWorkItem?.cancel()
        playbackStartTimeoutWorkItem = nil
        playbackStartGate.cancel()
    }

    private func applyPlaybackState(isPlaying: Bool) {
        guard let state = videoState else { return }
        guard isPlaying else {
            cancelPlaybackStart()
            player?.pause()
            retryPausedFilterRefreshIfNeeded()
            return
        }
        guard state.isVideoLoaded, player != nil else {
            cancelPlaybackStart()
            player?.pause()
            let rejectedRevision = state.playbackIntentRevision
            DispatchQueue.main.async { [weak state] in
                guard let state,
                      state.playbackIntentRevision == rejectedRevision,
                      state.isPlaying else { return }
                state.setPlaybackIntent(false)
            }
            return
        }
        guard !state.isScrubbing else {
            cancelPlaybackStart()
            return
        }
        let intentRevision = state.playbackIntentRevision
        if frameSeekCoordinator.authorizePendingResume(
            intentRevision: intentRevision
        ) {
            cancelPlaybackStart()
            player?.pause()
            return
        }
        if timeSeekInFlightToken != nil {
            cancelPlaybackStart()
            timeSeekResumeIntentRevision = intentRevision
            player?.pause()
            return
        }
        if state.isAtEnd {
            cancelPlaybackStart()
            if let timeline = frameTimeline, !timeline.isEmpty {
                let target = frameSeekCoordinator.begin(
                    frame: 0,
                    timeline: timeline,
                    resumeIntentRevision: intentRevision
                )
                performExactSeek(to: target, timeline: timeline)
            } else {
                performTimeSeek(
                    to: 0,
                    accurate: true,
                    resumeIntentRevision: intentRevision
                )
            }
        } else {
            startPlayerPlayback(
                intentRevision: intentRevision,
                publishedIntent: true
            )
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
            startPlayerPlayback(
                intentRevision: state.playbackIntentRevision
            )
        }
    }

    private func failLoad(_ error: Error, token: UUID) {
        guard loadToken == token, failedLoadToken != token else { return }
        failedLoadToken = token
        let state = videoState
        let message = error.localizedDescription
        state?.cancelScrubbing()
        cleanup()
        state?.setPlaybackIntent(false)
        state?.isVideoLoading = false
        state?.isVideoLoaded = false
        state?.isAtEnd = false
        state?.currentTime = 0
        state?.currentFrame = 0
        state?.duration = 0
        state?.totalFrames = 0
        state?.frameNavigationPrecision = .unavailable
        state?.frameNavigationMessage = nil
        state?.videoNaturalSize = .zero
        state?.videoErrorMessage = message
    }

    private func cleanup() {
        loadTask?.cancel()
        loadTask = nil
        loadToken = UUID()
        filterToken = UUID()
        frameSeekCoordinator.reset()
        previewSeekCoordinator.cancel()
        timeSeekToken = UUID()
        timeSeekInFlightToken = nil
        timeSeekResumeIntentRevision = nil
        frameTimeline = nil
        selectedVideoTrackID = nil
        playerIsReady = false
        metadataIsReady = false
        cancelPlaybackStart()
        filterRefreshWorkItem?.cancel()
        filterRefreshWorkItem = nil
        filterRefreshCoordinator.cancel()
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
        playerLayer.player = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerItem = nil
        currentAsset = nil
        player = nil
        // This is intentionally last. A cancelled load task or callback may
        // retain the same lease until its cooperative teardown actually ends.
        activeResourceLease = nil
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
            advancedFilters: state.effectiveAdvancedFilters,
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
            filterRefreshCoordinator.cancel()
            playerItem.videoComposition = nil
            return
        }

        if let filterComposition {
            playerItem.videoComposition = filterComposition
            schedulePausedFilterRefresh()
            return
        }

        guard !filterBuildInProgress,
              let resourceLease = activeResourceLease else { return }
        filterBuildInProgress = true
        let token = UUID()
        filterToken = token
        let generation = loadToken
        let pipelineState = filterPipelineState
        let context = ciContext

        AVVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { [resourceLease] request in
                defer { withExtendedLifetime(resourceLease) {} }
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
            completionHandler: {
                [weak self, weak playerItem, resourceLease] composition, error in
                DispatchQueue.main.async {
                    defer { withExtendedLifetime(resourceLease) {} }
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
        filterRefreshCoordinator.request()
        filterRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performPausedFilterRefreshIfReady()
        }
        filterRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func retryPausedFilterRefreshIfNeeded() {
        guard filterRefreshCoordinator.isPending else { return }
        filterRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performPausedFilterRefreshIfReady()
        }
        filterRefreshWorkItem = work
        DispatchQueue.main.async(execute: work)
    }

    private func performPausedFilterRefreshIfReady() {
        guard let state = videoState,
              let player else { return }
        let hasAuthoritativeSeek = frameSeekCoordinator.hasPendingSeek
            || previewSeekCoordinator.hasPendingSeek
            || timeSeekInFlightToken != nil
            || state.isScrubbing
        guard filterRefreshCoordinator.consumeIfReady(
            isPlaying: state.isPlaying,
            hasPendingSeek: hasAuthoritativeSeek
        ) else { return }

        filterRefreshWorkItem = nil
        let time = player.currentTime()
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Mouse Handling

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        videoState?.isVideoLoaded == true && videoState?.isLocked == false
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            cancelPointerPan()
        }
        super.viewWillMove(toWindow: newWindow)
    }

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
        cancelPointerPan()
    }

    override func cancelOperation(_ sender: Any?) {
        cancelPointerPan()
        super.cancelOperation(sender)
    }

    private func cancelPointerPan() {
        guard pointerPanSession != nil else { return }
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
