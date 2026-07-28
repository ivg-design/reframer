import AVFoundation
import XCTest
@testable import Reframer

final class VideoFrameTimelineTests: XCTestCase {
    func testVariableFrameRateLookupUsesPresentationTimes() {
        let timeline = VideoFrameTimeline(
            presentationTimes: [
                CMTime(seconds: 0.000, preferredTimescale: 1_000),
                CMTime(seconds: 0.040, preferredTimescale: 1_000),
                CMTime(seconds: 0.100, preferredTimescale: 1_000),
                CMTime(seconds: 0.133, preferredTimescale: 1_000)
            ],
            nominalFrameRate: 0
        )

        XCTAssertEqual(
            timeline.frameIndex(containing: CMTime(seconds: 0.080, preferredTimescale: 1_000)),
            1
        )
        XCTAssertEqual(
            timeline.nearestFrameIndex(to: CMTime(seconds: 0.080, preferredTimescale: 1_000)),
            2
        )
        XCTAssertEqual(CMTimeGetSeconds(timeline.time(forFrame: 3)), 0.133, accuracy: 0.000_001)
    }

    func testTimelineClampsFrameEntryToRealSamples() {
        let timeline = makeTimeline(count: 4)

        XCTAssertEqual(timeline.clampedIndex(-10), 0)
        XCTAssertEqual(timeline.clampedIndex(99), 3)
    }

    func testRapidStepBurstAccumulatesFromDesiredFrame() {
        let timeline = makeTimeline(count: 10)
        var coordinator = FrameSeekCoordinator()

        XCTAssertEqual(coordinator.target(from: 0, delta: 1, timeline: timeline).frame, 1)
        let stale = coordinator.target(from: 0, delta: 1, timeline: timeline)
        XCTAssertEqual(stale.frame, 2)
        let latest = coordinator.target(from: 0, delta: 1, timeline: timeline)
        XCTAssertEqual(latest.frame, 3)
        XCTAssertEqual(coordinator.desiredFrame, 3)

        coordinator.complete(stale)
        XCTAssertEqual(coordinator.desiredFrame, 3, "A stale seek completion must not win")
        coordinator.complete(latest)
        XCTAssertNil(coordinator.desiredFrame)
    }

    func testRepeatedFrameCannotBeCompletedByAnOlderGeneration() {
        let timeline = makeTimeline(count: 4)
        var coordinator = FrameSeekCoordinator()

        let firstFrameOne = coordinator.begin(frame: 1, timeline: timeline)
        _ = coordinator.begin(frame: 2, timeline: timeline)
        let latestFrameOne = coordinator.begin(frame: 1, timeline: timeline)

        coordinator.complete(firstFrameOne)
        XCTAssertEqual(coordinator.desiredTarget, latestFrameOne)
        coordinator.complete(latestFrameOne)
        XCTAssertNil(coordinator.desiredTarget)
    }

    func testFractionalFrameRateFixtureHasExactSampleCount() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "test-video", withExtension: "mp4"))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let nominalRate = try await Double(track.load(.nominalFrameRate))
        let duration = try await asset.load(.duration)

        let timeline = try await VideoFrameTimeline.load(
            asset: asset,
            track: track,
            nominalFrameRate: nominalRate
        )

        XCTAssertEqual(timeline.count, 1_291)
        XCTAssertEqual(timeline.nominalFrameRate, 29.97, accuracy: 0.01)
        XCTAssertEqual(CMTimeGetSeconds(timeline.time(forFrame: 0)), 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(CMTimeGetSeconds(timeline.time(forFrame: 1_290)), 43)
        XCTAssertLessThan(
            CMTimeGetSeconds(timeline.time(forFrame: 1_290)),
            CMTimeGetSeconds(duration)
        )
    }

    private func makeTimeline(count: Int) -> VideoFrameTimeline {
        VideoFrameTimeline(
            presentationTimes: (0..<count).map {
                CMTime(value: CMTimeValue($0), timescale: 30)
            },
            nominalFrameRate: 30
        )
    }
}
