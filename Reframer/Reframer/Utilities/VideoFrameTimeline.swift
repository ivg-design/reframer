import AVFoundation
import CoreMedia

enum VideoFrameTimelineError: LocalizedError {
    case sampleCursorUnavailable
    case noVideoSamples

    var errorDescription: String? {
        switch self {
        case .sampleCursorUnavailable:
            return "The video's presentation samples could not be indexed."
        case .noVideoSamples:
            return "The file does not contain any readable video frames."
        }
    }
}

/// Exact presentation timestamps for the decoded samples in one video track.
///
/// Reframer uses this table instead of multiplying time by a rounded nominal
/// frame rate. That keeps frame entry, stepping, VFR media, and fractional
/// frame-rate media on the asset's real sample boundaries.
struct VideoFrameTimeline {
    enum Precision: Equatable {
        case exact
        case estimated
    }

    private enum Storage {
        case exact([CMTime])
        case estimated(frameCount: Int, frameDuration: CMTime)
    }

    private let storage: Storage
    let nominalFrameRate: Double
    let precision: Precision

    var count: Int {
        switch storage {
        case .exact(let presentationTimes):
            return presentationTimes.count
        case .estimated(let frameCount, _):
            return frameCount
        }
    }

    var isEmpty: Bool { count == 0 }
    var isExact: Bool { precision == .exact }

    init(presentationTimes: [CMTime], nominalFrameRate: Double) {
        var sorted = presentationTimes
            .filter { $0.isValid && $0.isNumeric && CMTimeCompare($0, .zero) >= 0 }
            .sorted { CMTimeCompare($0, $1) < 0 }

        if sorted.count > 1 {
            var unique: [CMTime] = []
            unique.reserveCapacity(sorted.count)
            for time in sorted where unique.last.map({ CMTimeCompare($0, time) != 0 }) ?? true {
                unique.append(time)
            }
            sorted = unique
        }

        storage = .exact(sorted)
        precision = .exact
        self.nominalFrameRate = Self.resolvedFrameRate(
            preferred: nominalFrameRate,
            presentationTimes: sorted
        )
    }

    /// Creates a virtual, constant-rate frame table for playable media whose
    /// exact sample cursor cannot be indexed. No per-frame array is allocated,
    /// so long videos remain bounded in memory.
    static func estimated(duration: CMTime, nominalFrameRate: Double) -> VideoFrameTimeline? {
        let durationSeconds = CMTimeGetSeconds(duration)
        guard duration.isValid,
              duration.isNumeric,
              durationSeconds.isFinite,
              durationSeconds > 0 else { return nil }

        let frameRate = nominalFrameRate.isFinite && nominalFrameRate > 0
            ? nominalFrameRate
            : 30
        let frameCountValue = ceil(durationSeconds * frameRate)
        guard frameCountValue.isFinite,
              frameCountValue >= 1,
              frameCountValue < Double(Int.max) else { return nil }

        let frameDuration = CMTime(
            seconds: 1 / frameRate,
            preferredTimescale: 600_000
        )
        guard frameDuration.isValid,
              frameDuration.isNumeric,
              CMTimeCompare(frameDuration, .zero) > 0 else { return nil }

        return VideoFrameTimeline(
            storage: .estimated(
                frameCount: Int(frameCountValue),
                frameDuration: frameDuration
            ),
            nominalFrameRate: frameRate,
            precision: .estimated
        )
    }

    private init(storage: Storage, nominalFrameRate: Double, precision: Precision) {
        self.storage = storage
        self.nominalFrameRate = nominalFrameRate
        self.precision = precision
    }

    func clampedIndex(_ index: Int) -> Int {
        guard !isEmpty else { return 0 }
        return max(0, min(count - 1, index))
    }

    func time(forFrame index: Int) -> CMTime {
        guard !isEmpty else { return .zero }
        let clamped = clampedIndex(index)
        switch storage {
        case .exact(let presentationTimes):
            return presentationTimes[clamped]
        case .estimated(_, let frameDuration):
            return CMTimeMultiplyByFloat64(frameDuration, multiplier: Double(clamped))
        }
    }

    /// Returns the sample whose presentation interval contains `time`.
    func frameIndex(containing time: CMTime) -> Int {
        guard !isEmpty, time.isValid, time.isNumeric else { return 0 }

        switch storage {
        case .exact(let presentationTimes):
            var lower = 0
            var upper = count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if CMTimeCompare(presentationTimes[middle], time) <= 0 {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return clampedIndex(lower - 1)
        case .estimated(_, let frameDuration):
            let seconds = CMTimeGetSeconds(time)
            let frameSeconds = CMTimeGetSeconds(frameDuration)
            guard seconds.isFinite,
                  frameSeconds.isFinite,
                  frameSeconds > 0 else { return 0 }
            let rawIndex = floor(max(0, seconds) / frameSeconds)
            guard rawIndex < Double(Int.max) else { return count - 1 }
            return clampedIndex(Int(rawIndex))
        }
    }

    /// Returns the closest exact sample boundary to an arbitrary scrub time.
    func nearestFrameIndex(to time: CMTime) -> Int {
        let earlier = frameIndex(containing: time)
        let later = min(count - 1, earlier + 1)
        guard later != earlier else { return earlier }

        let earlierDistance = abs(CMTimeGetSeconds(CMTimeSubtract(time, self.time(forFrame: earlier))))
        let laterDistance = abs(CMTimeGetSeconds(CMTimeSubtract(self.time(forFrame: later), time)))
        return laterDistance < earlierDistance ? later : earlier
    }

    static func load(
        asset: AVAsset,
        track: AVAssetTrack,
        nominalFrameRate: Double
    ) async throws -> VideoFrameTimeline {
        let segments = try await track.load(.segments)
        try Task.checkCancellation()
        let canProvideSampleCursors = try await track.load(.canProvideSampleCursors)
        try Task.checkCancellation()
        return try await runStructuredIndexing {
            let times = try mappedPresentationTimes(
                track: track,
                segments: segments,
                canProvideSampleCursors: canProvideSampleCursors
            )
            return VideoFrameTimeline(
                presentationTimes: times,
                nominalFrameRate: nominalFrameRate
            )
        }
    }

    /// Runs CPU-bound sample indexing as a structured child task. Cancelling
    /// the caller cancels the child and the task group waits for its teardown.
    static func runStructuredIndexing<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated, operation: operation)
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    /// Enumerates one entry per presentation sample, then translates timestamps
    /// from the media's source timeline into the timeline consumed by AVPlayer.
    ///
    /// AVAssetReader buffers are intentionally not used here: compressed media
    /// can yield sentinel or duplicate buffers, and raw PTS values can include
    /// an edit-list offset that does not exist on the player timeline.
    private static func mappedPresentationTimes(
        track: AVAssetTrack,
        segments: [AVAssetTrackSegment],
        canProvideSampleCursors: Bool
    ) throws -> [CMTime] {
        guard canProvideSampleCursors,
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else {
            throw VideoFrameTimelineError.sampleCursorUnavailable
        }

        // The first sample in decode order can follow an earlier B-frame in
        // presentation order. Walk backwards before enumerating forwards.
        while cursor.stepInPresentationOrder(byCount: -1) != 0 {
            try Task.checkCancellation()
        }

        var sourceTimes: [CMTime] = []
        repeat {
            try Task.checkCancellation()
            let time = cursor.presentationTimeStamp
            if time.isValid && time.isNumeric {
                sourceTimes.append(time)
            }
        } while cursor.stepInPresentationOrder(byCount: 1) != 0
        sourceTimes.sort { CMTimeCompare($0, $1) < 0 }

        var targetTimes: [CMTime] = []
        for segment in segments where !segment.isEmpty {
            try Task.checkCancellation()
            let mapping = segment.timeMapping
            guard mapping.source.isValid,
                  mapping.target.isValid,
                  mapping.source.duration.isNumeric,
                  mapping.target.duration.isNumeric else { continue }

            for sourceTime in sourceTimes
            where CMTimeRangeContainsTime(mapping.source, time: sourceTime) {
                try Task.checkCancellation()
                let targetTime = CMTimeMapTimeFromRangeToRange(
                    sourceTime,
                    fromRange: mapping.source,
                    toRange: mapping.target
                )
                if targetTime.isValid,
                   targetTime.isNumeric,
                   CMTimeCompare(targetTime, .zero) >= 0 {
                    targetTimes.append(targetTime)
                }
            }
        }

        targetTimes.sort { CMTimeCompare($0, $1) < 0 }
        var unique: [CMTime] = []
        unique.reserveCapacity(targetTimes.count)
        for time in targetTimes
        where unique.last.map({ CMTimeCompare($0, time) != 0 }) ?? true {
            unique.append(time)
        }
        guard !unique.isEmpty else {
            throw VideoFrameTimelineError.noVideoSamples
        }
        return unique
    }

    private static func resolvedFrameRate(
        preferred: Double,
        presentationTimes: [CMTime]
    ) -> Double {
        if preferred.isFinite && preferred > 0 {
            return preferred
        }

        let deltas = zip(presentationTimes, presentationTimes.dropFirst())
            .map { CMTimeGetSeconds(CMTimeSubtract($1, $0)) }
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard !deltas.isEmpty else { return 0 }
        return 1.0 / deltas[deltas.count / 2]
    }
}

struct FrameSeekTarget: Equatable {
    let frame: Int
    let generation: UInt64
}

/// Maintains the requested sample as the authority while AVPlayer completes
/// asynchronous seeks. Rapid step bursts therefore accumulate instead of
/// repeatedly stepping from the last displayed sample.
struct FrameSeekCoordinator {
    private(set) var desiredTarget: FrameSeekTarget?
    private var nextGeneration: UInt64 = 0

    var desiredFrame: Int? { desiredTarget?.frame }
    var hasPendingSeek: Bool { desiredTarget != nil }

    mutating func reset() {
        desiredTarget = nil
        nextGeneration &+= 1
    }

    mutating func target(
        from displayedFrame: Int,
        delta: Int,
        timeline: VideoFrameTimeline
    ) -> FrameSeekTarget {
        let base = desiredTarget?.frame ?? displayedFrame
        let (sum, overflowed) = base.addingReportingOverflow(delta)
        let requested = overflowed ? (delta >= 0 ? Int.max : Int.min) : sum
        return makeTarget(frame: timeline.clampedIndex(requested))
    }

    mutating func begin(frame: Int, timeline: VideoFrameTimeline) -> FrameSeekTarget {
        makeTarget(frame: timeline.clampedIndex(frame))
    }

    mutating func complete(_ target: FrameSeekTarget) {
        if desiredTarget == target {
            desiredTarget = nil
        }
    }

    private mutating func makeTarget(frame: Int) -> FrameSeekTarget {
        nextGeneration &+= 1
        let target = FrameSeekTarget(frame: frame, generation: nextGeneration)
        desiredTarget = target
        return target
    }
}

struct PreviewSeekTarget: Equatable {
    let time: Double
    let generation: UInt64
}

enum PreviewSeekAction: Equatable {
    case start(PreviewSeekTarget)
    case queued
}

/// Bounds scrub traffic to one in-flight player seek plus one replaceable
/// latest request. A generation protects against stale and ABA completions.
struct PreviewSeekCoordinator {
    private(set) var inFlight: PreviewSeekTarget?
    private(set) var queuedLatest: PreviewSeekTarget?
    private var nextGeneration: UInt64 = 0

    var hasPendingSeek: Bool {
        inFlight != nil || queuedLatest != nil
    }

    mutating func submit(time: Double) -> PreviewSeekAction {
        nextGeneration &+= 1
        let target = PreviewSeekTarget(time: time, generation: nextGeneration)
        guard inFlight != nil else {
            inFlight = target
            return .start(target)
        }
        queuedLatest = target
        return .queued
    }

    mutating func complete(_ target: PreviewSeekTarget) -> PreviewSeekTarget? {
        guard inFlight == target else { return nil }
        inFlight = nil
        guard let next = queuedLatest else { return nil }
        queuedLatest = nil
        inFlight = next
        return next
    }

    mutating func cancel() {
        inFlight = nil
        queuedLatest = nil
        nextGeneration &+= 1
    }
}

/// Remembers a paused-frame filter refresh until no authoritative seek is
/// pending. A blocked refresh is never silently dropped.
struct DeferredRefreshCoordinator {
    private(set) var isPending = false

    mutating func request() {
        isPending = true
    }

    mutating func cancel() {
        isPending = false
    }

    mutating func consumeIfReady(isPlaying: Bool, hasPendingSeek: Bool) -> Bool {
        guard isPending, !isPlaying, !hasPendingSeek else { return false }
        isPending = false
        return true
    }
}
