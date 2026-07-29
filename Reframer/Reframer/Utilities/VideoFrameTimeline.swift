import AVFoundation
import CoreMedia

enum VideoFrameTimelineError: LocalizedError {
    case sampleCursorUnavailable
    case noVideoSamples
    case exactSampleLimitExceeded(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .sampleCursorUnavailable:
            return "The video's presentation samples could not be indexed."
        case .noVideoSamples:
            return "The file does not contain any readable video frames."
        case .exactSampleLimitExceeded(let maximum):
            return "The video contains more than \(maximum) presentation samples, so exact frame indexing was skipped."
        }
    }
}

struct VideoFrameSegmentMapping: Sendable {
    let source: CMTimeRange
    let target: CMTimeRange
}

/// Exact presentation timestamps for the decoded samples in one video track.
///
/// Reframer uses this table instead of multiplying time by a rounded nominal
/// frame rate. That keeps frame entry, stepping, VFR media, and fractional
/// frame-rate media on the asset's real sample boundaries.
struct VideoFrameTimeline {
    /// Caps exact indexing at roughly 46 MiB for the final CMTime table and
    /// bounds temporary mapping storage. Larger media keeps the virtual,
    /// constant-rate fallback instead of risking an unbounded memory spike.
    static let maximumExactSampleCount = 2_000_000

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
        sorted.sort { CMTimeCompare($0, $1) < 0 }
        Self.deduplicateSortedTimesInPlace(&sorted)

        storage = .exact(sorted)
        precision = .exact
        self.nominalFrameRate = Self.resolvedFrameRate(
            preferred: nominalFrameRate,
            presentationTimes: sorted
        )
    }

    private init(
        sortedPresentationTimes: [CMTime],
        nominalFrameRate: Double
    ) {
        storage = .exact(sortedPresentationTimes)
        precision = .exact
        self.nominalFrameRate = Self.resolvedFrameRate(
            preferred: nominalFrameRate,
            presentationTimes: sortedPresentationTimes
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
                canProvideSampleCursors: canProvideSampleCursors,
                maximumSampleCount: maximumExactSampleCount
            )
            return VideoFrameTimeline(
                sortedPresentationTimes: times,
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
        canProvideSampleCursors: Bool,
        maximumSampleCount: Int
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
        sourceTimes.reserveCapacity(min(maximumSampleCount, 240_000))
        var visitedSampleCount = 0
        repeat {
            try Task.checkCancellation()
            visitedSampleCount += 1
            guard visitedSampleCount <= maximumSampleCount else {
                throw VideoFrameTimelineError.exactSampleLimitExceeded(
                    maximum: maximumSampleCount
                )
            }
            let time = cursor.presentationTimeStamp
            if time.isValid,
               time.isNumeric,
               sourceTimes.last.map({ CMTimeCompare($0, time) != 0 }) ?? true {
                sourceTimes.append(time)
            }
        } while cursor.stepInPresentationOrder(byCount: 1) != 0

        let mappings = segments
            .filter { !$0.isEmpty }
            .map {
                VideoFrameSegmentMapping(
                    source: $0.timeMapping.source,
                    target: $0.timeMapping.target
                )
            }
        let mapped = try mapSortedPresentationTimes(
            sourceTimes,
            through: mappings,
            maximumSampleCount: maximumSampleCount
        )
        guard !mapped.isEmpty else {
            throw VideoFrameTimelineError.noVideoSamples
        }
        return mapped
    }

    /// Maps a presentation-ordered sample table through target-ordered edit
    /// segments. Binary bounds avoid rescanning every sample for every segment.
    /// The normal asset path is already sorted; an in-place fallback sort is
    /// needed only for malformed or overlapping target mappings.
    static func mapSortedPresentationTimes(
        _ sourceTimes: [CMTime],
        through mappings: [VideoFrameSegmentMapping],
        maximumSampleCount: Int = maximumExactSampleCount
    ) throws -> [CMTime] {
        guard maximumSampleCount > 0 else {
            throw VideoFrameTimelineError.exactSampleLimitExceeded(
                maximum: maximumSampleCount
            )
        }
        guard sourceTimes.count <= maximumSampleCount else {
            throw VideoFrameTimelineError.exactSampleLimitExceeded(
                maximum: maximumSampleCount
            )
        }

        let validMappings = mappings
            .filter {
                $0.source.isValid
                    && $0.target.isValid
                    && $0.source.start.isNumeric
                    && $0.target.start.isNumeric
                    && $0.source.duration.isNumeric
                    && $0.target.duration.isNumeric
                    && CMTimeCompare($0.source.duration, .zero) > 0
                    && CMTimeCompare($0.target.duration, .zero) > 0
            }
            .sorted {
                let targetOrder = CMTimeCompare($0.target.start, $1.target.start)
                if targetOrder != 0 {
                    return targetOrder < 0
                }
                return CMTimeCompare($0.source.start, $1.source.start) < 0
            }

        var targetTimes: [CMTime] = []
        targetTimes.reserveCapacity(min(sourceTimes.count, maximumSampleCount))
        var requiresNormalization = false

        for mapping in validMappings {
            try Task.checkCancellation()
            let sourceEnd = CMTimeRangeGetEnd(mapping.source)
            guard sourceEnd.isValid, sourceEnd.isNumeric else { continue }
            let lower = lowerBound(
                in: sourceTimes,
                for: mapping.source.start
            )
            let upper = lowerBound(in: sourceTimes, for: sourceEnd)
            guard lower < upper else { continue }

            for sourceTime in sourceTimes[lower..<upper] {
                try Task.checkCancellation()
                guard CMTimeRangeContainsTime(mapping.source, time: sourceTime) else {
                    continue
                }
                let targetTime = CMTimeMapTimeFromRangeToRange(
                    sourceTime,
                    fromRange: mapping.source,
                    toRange: mapping.target
                )
                guard targetTime.isValid,
                      targetTime.isNumeric,
                      CMTimeCompare(targetTime, .zero) >= 0 else { continue }

                if let previous = targetTimes.last {
                    let order = CMTimeCompare(previous, targetTime)
                    if order == 0 {
                        continue
                    }
                    if order > 0 {
                        requiresNormalization = true
                    }
                }
                guard targetTimes.count < maximumSampleCount else {
                    throw VideoFrameTimelineError.exactSampleLimitExceeded(
                        maximum: maximumSampleCount
                    )
                }
                targetTimes.append(targetTime)
            }
        }

        if requiresNormalization {
            targetTimes.sort { CMTimeCompare($0, $1) < 0 }
            deduplicateSortedTimesInPlace(&targetTimes)
        }
        return targetTimes
    }

    private static func lowerBound(in values: [CMTime], for target: CMTime) -> Int {
        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if CMTimeCompare(values[middle], target) < 0 {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func deduplicateSortedTimesInPlace(_ values: inout [CMTime]) {
        guard values.count > 1 else { return }
        var writeIndex = 1
        for readIndex in 1..<values.count
        where CMTimeCompare(values[writeIndex - 1], values[readIndex]) != 0 {
            if writeIndex != readIndex {
                values[writeIndex] = values[readIndex]
            }
            writeIndex += 1
        }
        if writeIndex < values.count {
            values.removeSubrange(writeIndex...)
        }
    }

    private static func resolvedFrameRate(
        preferred: Double,
        presentationTimes: [CMTime]
    ) -> Double {
        if preferred.isFinite && preferred > 0 {
            return preferred
        }

        var duration = 0.0
        var intervalCount = 0
        for (earlier, later) in zip(
            presentationTimes,
            presentationTimes.dropFirst()
        ) {
            let delta = CMTimeGetSeconds(CMTimeSubtract(later, earlier))
            if delta.isFinite, delta > 0 {
                duration += delta
                intervalCount += 1
            }
        }
        guard intervalCount > 0, duration.isFinite, duration > 0 else { return 0 }
        return Double(intervalCount) / duration
    }
}

struct FrameSeekTarget: Equatable {
    let frame: Int
    let generation: UInt64
    let requestedTime: CMTime
    /// The exact user-intent revision that authorized playback to resume
    /// after this asynchronous seek. A nil value means the seek must remain
    /// paused.
    let resumeIntentRevision: UInt64?
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
        return makeTarget(
            frame: timeline.clampedIndex(requested),
            timeline: timeline,
            resumeIntentRevision: nil
        )
    }

    mutating func begin(
        frame: Int,
        timeline: VideoFrameTimeline,
        resumeIntentRevision: UInt64? = nil
    ) -> FrameSeekTarget {
        makeTarget(
            frame: timeline.clampedIndex(frame),
            timeline: timeline,
            resumeIntentRevision: resumeIntentRevision
        )
    }

    /// Reissues the latest logical request against a newly authoritative
    /// timeline. Mapping by presentation time avoids treating an estimated
    /// constant-rate ordinal as an exact decoded-sample ordinal for VFR media.
    mutating func promote(to timeline: VideoFrameTimeline) -> FrameSeekTarget? {
        guard let desiredTarget, !timeline.isEmpty else { return nil }
        return makeTarget(
            frame: timeline.nearestFrameIndex(to: desiredTarget.requestedTime),
            timeline: timeline,
            resumeIntentRevision: desiredTarget.resumeIntentRevision
        )
    }

    /// Attaches the latest Play command to the in-flight logical seek without
    /// issuing a competing `AVPlayer.play()` while that seek is unresolved.
    mutating func authorizePendingResume(intentRevision: UInt64) -> Bool {
        guard let desiredTarget else { return false }
        self.desiredTarget = FrameSeekTarget(
            frame: desiredTarget.frame,
            generation: desiredTarget.generation,
            requestedTime: desiredTarget.requestedTime,
            resumeIntentRevision: intentRevision
        )
        return true
    }

    /// Completes by generation so a newer Play revision may update the
    /// in-flight target without making its seek completion appear stale.
    @discardableResult
    mutating func complete(_ target: FrameSeekTarget) -> FrameSeekTarget? {
        guard let desiredTarget,
              desiredTarget.generation == target.generation else {
            return nil
        }
        self.desiredTarget = nil
        return desiredTarget
    }

    private mutating func makeTarget(
        frame: Int,
        timeline: VideoFrameTimeline,
        resumeIntentRevision: UInt64?
    ) -> FrameSeekTarget {
        nextGeneration &+= 1
        let target = FrameSeekTarget(
            frame: frame,
            generation: nextGeneration,
            requestedTime: timeline.time(forFrame: frame),
            resumeIntentRevision: resumeIntentRevision
        )
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
