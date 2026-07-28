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
    let presentationTimes: [CMTime]
    let nominalFrameRate: Double

    var count: Int { presentationTimes.count }
    var isEmpty: Bool { presentationTimes.isEmpty }

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

        self.presentationTimes = sorted
        self.nominalFrameRate = Self.resolvedFrameRate(
            preferred: nominalFrameRate,
            presentationTimes: sorted
        )
    }

    func clampedIndex(_ index: Int) -> Int {
        guard !isEmpty else { return 0 }
        return max(0, min(count - 1, index))
    }

    func time(forFrame index: Int) -> CMTime {
        guard !isEmpty else { return .zero }
        return presentationTimes[clampedIndex(index)]
    }

    /// Returns the sample whose presentation interval contains `time`.
    func frameIndex(containing time: CMTime) -> Int {
        guard !isEmpty, time.isValid, time.isNumeric else { return 0 }

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
    }

    /// Returns the closest exact sample boundary to an arbitrary scrub time.
    func nearestFrameIndex(to time: CMTime) -> Int {
        let earlier = frameIndex(containing: time)
        let later = min(count - 1, earlier + 1)
        guard later != earlier else { return earlier }

        let earlierDistance = abs(CMTimeGetSeconds(CMTimeSubtract(time, presentationTimes[earlier])))
        let laterDistance = abs(CMTimeGetSeconds(CMTimeSubtract(presentationTimes[later], time)))
        return laterDistance < earlierDistance ? later : earlier
    }

    static func load(
        asset: AVAsset,
        track: AVAssetTrack,
        nominalFrameRate: Double
    ) async throws -> VideoFrameTimeline {
        let segments = try await track.load(.segments)
        let canProvideSampleCursors = try await track.load(.canProvideSampleCursors)
        return try await Task.detached(priority: .userInitiated) {
            let times = try mappedPresentationTimes(
                track: track,
                segments: segments,
                canProvideSampleCursors: canProvideSampleCursors
            )
            return VideoFrameTimeline(
                presentationTimes: times,
                nominalFrameRate: nominalFrameRate
            )
        }.value
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
        while cursor.stepInPresentationOrder(byCount: -1) != 0 {}

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
            let mapping = segment.timeMapping
            guard mapping.source.isValid,
                  mapping.target.isValid,
                  mapping.source.duration.isNumeric,
                  mapping.target.duration.isNumeric else { continue }

            for sourceTime in sourceTimes
            where CMTimeRangeContainsTime(mapping.source, time: sourceTime) {
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
        return makeTarget(frame: timeline.clampedIndex(base + delta))
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
