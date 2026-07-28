import AVFoundation
import XCTest
@testable import Reframer

final class PlaybackStatusReconciliationTests: XCTestCase {
    func testDelayedPlayingStatusCannotResurrectPausedIntent() {
        XCTAssertFalse(
            PlaybackStatusReconciliation.intent(
                currentIntent: false,
                status: .playing,
                rate: 1,
                isScrubbing: false
            )
        )
    }

    func testInvoluntaryPauseClearsPlayingIntent() {
        XCTAssertFalse(
            PlaybackStatusReconciliation.intent(
                currentIntent: true,
                status: .paused,
                rate: 0,
                isScrubbing: false
            )
        )
    }

    func testScrubPausePreservesPlayingIntent() {
        XCTAssertTrue(
            PlaybackStatusReconciliation.intent(
                currentIntent: true,
                status: .paused,
                rate: 0,
                isScrubbing: true
            )
        )
    }
}

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

    func testExactTimelinePromotionPreservesTimeResumeAndGeneration() throws {
        let estimated = try XCTUnwrap(
            VideoFrameTimeline.estimated(
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                nominalFrameRate: 10
            )
        )
        let exact = VideoFrameTimeline(
            presentationTimes: [0, 0.08, 0.19, 0.31, 0.5].map {
                CMTime(seconds: $0, preferredTimescale: 10_000)
            },
            nominalFrameRate: 0
        )
        var coordinator = FrameSeekCoordinator()
        let estimatedTarget = coordinator.begin(
            frame: 3,
            timeline: estimated,
            resumePlayback: true
        )

        let promoted = try XCTUnwrap(coordinator.promote(to: exact))

        XCTAssertEqual(promoted.frame, 3)
        XCTAssertEqual(
            CMTimeGetSeconds(promoted.requestedTime),
            0.31,
            accuracy: 0.000_001
        )
        XCTAssertTrue(promoted.resumePlayback)
        XCTAssertNotEqual(promoted.generation, estimatedTarget.generation)

        coordinator.complete(estimatedTarget)
        XCTAssertEqual(
            coordinator.desiredTarget,
            promoted,
            "The superseded estimated completion must not clear exact intent"
        )
        coordinator.complete(promoted)
        XCTAssertFalse(coordinator.hasPendingSeek)
    }

    func testPromotionUsesLatestRapidStepIntentAndKeepsRefreshDeferred() throws {
        let estimated = try XCTUnwrap(
            VideoFrameTimeline.estimated(
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                nominalFrameRate: 10
            )
        )
        let exact = VideoFrameTimeline(
            presentationTimes: [0, 0.11, 0.21, 0.32, 0.39, 0.52].map {
                CMTime(seconds: $0, preferredTimescale: 10_000)
            },
            nominalFrameRate: 0
        )
        var seekCoordinator = FrameSeekCoordinator()
        let stale = seekCoordinator.target(
            from: 0,
            delta: 2,
            timeline: estimated
        )
        _ = seekCoordinator.target(from: 0, delta: 2, timeline: estimated)
        var refreshCoordinator = DeferredRefreshCoordinator()
        refreshCoordinator.request()

        let promoted = try XCTUnwrap(seekCoordinator.promote(to: exact))

        XCTAssertEqual(promoted.frame, 4, "Latest estimated time was 0.4 seconds")
        XCTAssertFalse(
            refreshCoordinator.consumeIfReady(
                isPlaying: false,
                hasPendingSeek: seekCoordinator.hasPendingSeek
            )
        )
        seekCoordinator.complete(stale)
        XCTAssertEqual(seekCoordinator.desiredTarget, promoted)
        XCTAssertTrue(refreshCoordinator.isPending)
        seekCoordinator.complete(promoted)
        XCTAssertTrue(
            refreshCoordinator.consumeIfReady(
                isPlaying: false,
                hasPendingSeek: seekCoordinator.hasPendingSeek
            )
        )
        XCTAssertFalse(refreshCoordinator.isPending)
        XCTAssertNil(seekCoordinator.promote(to: exact))
    }

    func testOneHundredRapidStepsAccumulateAndClamp() {
        let timeline = makeTimeline(count: 75)
        var coordinator = FrameSeekCoordinator()
        var target = coordinator.begin(frame: 0, timeline: timeline)

        for _ in 0..<100 {
            target = coordinator.target(from: 0, delta: 1, timeline: timeline)
        }
        XCTAssertEqual(target.frame, 74)

        for _ in 0..<100 {
            target = coordinator.target(from: 74, delta: -1, timeline: timeline)
        }
        XCTAssertEqual(target.frame, 0)
    }

    func testTenFrameStepsReverseFromDesiredTarget() {
        let timeline = makeTimeline(count: 100)
        var coordinator = FrameSeekCoordinator()

        XCTAssertEqual(
            coordinator.target(from: 20, delta: 10, timeline: timeline).frame,
            30
        )
        XCTAssertEqual(
            coordinator.target(from: 20, delta: 10, timeline: timeline).frame,
            40
        )
        XCTAssertEqual(
            coordinator.target(from: 20, delta: -10, timeline: timeline).frame,
            30
        )
    }

    func testEstimatedFractionalTimelineUsesVirtualFrameBoundaries() throws {
        let timeline = try XCTUnwrap(
            VideoFrameTimeline.estimated(
                duration: CMTime(value: 1_001, timescale: 100),
                nominalFrameRate: 24_000.0 / 1_001.0
            )
        )

        XCTAssertEqual(timeline.precision, .estimated)
        XCTAssertEqual(timeline.count, 240)
        XCTAssertEqual(timeline.nominalFrameRate, 24_000.0 / 1_001.0, accuracy: 0.000_001)
        XCTAssertEqual(
            CMTimeGetSeconds(timeline.time(forFrame: 239)),
            Double(239) * 1_001.0 / 24_000.0,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            timeline.nearestFrameIndex(
                to: CMTime(seconds: 5.005, preferredTimescale: 600_000)
            ),
            120
        )
    }

    func testEstimatedTimelineRejectsInvalidDurationAndFallsBackFromInvalidRate() throws {
        XCTAssertNil(
            VideoFrameTimeline.estimated(
                duration: .invalid,
                nominalFrameRate: 30
            )
        )

        let timeline = try XCTUnwrap(
            VideoFrameTimeline.estimated(
                duration: CMTime(seconds: 1, preferredTimescale: 600),
                nominalFrameRate: .nan
            )
        )
        XCTAssertEqual(timeline.count, 30)
        XCTAssertEqual(timeline.nominalFrameRate, 30)
    }

    func testExactSampleLimitIsExplicitAndEnforcedBeforeMapping() {
        XCTAssertEqual(VideoFrameTimeline.maximumExactSampleCount, 2_000_000)
        let sourceTimes = (0..<4).map {
            CMTime(value: CMTimeValue($0), timescale: 1)
        }
        let mapping = VideoFrameSegmentMapping(
            source: CMTimeRange(
                start: .zero,
                duration: CMTime(value: 4, timescale: 1)
            ),
            target: CMTimeRange(
                start: .zero,
                duration: CMTime(value: 4, timescale: 1)
            )
        )

        XCTAssertThrowsError(
            try VideoFrameTimeline.mapSortedPresentationTimes(
                sourceTimes,
                through: [mapping],
                maximumSampleCount: 3
            )
        ) { error in
            guard case VideoFrameTimelineError.exactSampleLimitExceeded(
                let maximum
            ) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(maximum, 3)
        }
    }

    func testSegmentMappingUsesBinarySlicesAndTargetOrder() throws {
        let sourceTimes = (0..<6).map {
            CMTime(value: CMTimeValue($0), timescale: 1)
        }
        // Deliberately provide the later target segment first. The source edit
        // also jumps backwards, as a reordered movie edit can.
        let mappings = [
            VideoFrameSegmentMapping(
                source: CMTimeRange(
                    start: .zero,
                    duration: CMTime(value: 2, timescale: 1)
                ),
                target: CMTimeRange(
                    start: CMTime(value: 2, timescale: 1),
                    duration: CMTime(value: 2, timescale: 1)
                )
            ),
            VideoFrameSegmentMapping(
                source: CMTimeRange(
                    start: CMTime(value: 3, timescale: 1),
                    duration: CMTime(value: 2, timescale: 1)
                ),
                target: CMTimeRange(
                    start: .zero,
                    duration: CMTime(value: 2, timescale: 1)
                )
            )
        ]

        let mapped = try VideoFrameTimeline.mapSortedPresentationTimes(
            sourceTimes,
            through: mappings
        )

        XCTAssertEqual(
            mapped.map(CMTimeGetSeconds),
            [0, 1, 2, 3]
        )
    }

    func testOverlappingMappingsNormalizeAndDeduplicateInPlace() throws {
        let sourceTimes = [0, 1, 2].map {
            CMTime(value: CMTimeValue($0), timescale: 1)
        }
        let fullRange = CMTimeRange(
            start: .zero,
            duration: CMTime(value: 3, timescale: 1)
        )

        let mapped = try VideoFrameTimeline.mapSortedPresentationTimes(
            sourceTimes,
            through: [
                VideoFrameSegmentMapping(
                    source: fullRange,
                    target: fullRange
                ),
                VideoFrameSegmentMapping(
                    source: fullRange,
                    target: fullRange
                )
            ]
        )

        XCTAssertEqual(mapped.map(CMTimeGetSeconds), [0, 1, 2])
    }

    func testPreviewSeeksAreBoundedAndLatestWins() {
        var coordinator = PreviewSeekCoordinator()
        let firstAction = coordinator.submit(time: 0)
        guard case .start(let first) = firstAction else {
            return XCTFail("The first preview must start immediately")
        }

        for index in 1...100 {
            XCTAssertEqual(coordinator.submit(time: Double(index)), .queued)
        }

        XCTAssertEqual(coordinator.inFlight, first)
        XCTAssertEqual(coordinator.queuedLatest?.time, 100)
        let next = coordinator.complete(first)
        XCTAssertEqual(next?.time, 100)
        XCTAssertEqual(coordinator.inFlight, next)
        XCTAssertNil(coordinator.queuedLatest)
        XCTAssertNil(coordinator.complete(PreviewSeekTarget(time: 50, generation: 50)))
        XCTAssertNil(coordinator.complete(try! XCTUnwrap(next)))
        XCTAssertFalse(coordinator.hasPendingSeek)
    }

    func testPreviewCancellationInvalidatesStaleABACompletion() {
        var coordinator = PreviewSeekCoordinator()
        guard case .start(let first) = coordinator.submit(time: 1) else {
            return XCTFail("Expected an in-flight preview")
        }
        coordinator.cancel()
        guard case .start(let replacement) = coordinator.submit(time: 1) else {
            return XCTFail("Expected a replacement preview")
        }

        XCTAssertNotEqual(first, replacement)
        XCTAssertNil(coordinator.complete(first))
        XCTAssertEqual(coordinator.inFlight, replacement)
        XCTAssertNil(coordinator.complete(replacement))
        XCTAssertFalse(coordinator.hasPendingSeek)
    }

    func testDeferredRefreshSurvivesSeekAndRunsOnceWhenReady() {
        var coordinator = DeferredRefreshCoordinator()
        coordinator.request()

        XCTAssertFalse(coordinator.consumeIfReady(isPlaying: false, hasPendingSeek: true))
        XCTAssertTrue(coordinator.isPending)
        XCTAssertFalse(coordinator.consumeIfReady(isPlaying: true, hasPendingSeek: false))
        XCTAssertTrue(coordinator.isPending)
        XCTAssertTrue(coordinator.consumeIfReady(isPlaying: false, hasPendingSeek: false))
        XCTAssertFalse(coordinator.isPending)
        XCTAssertFalse(coordinator.consumeIfReady(isPlaying: false, hasPendingSeek: false))
    }

    func testStructuredIndexingPropagatesCancellation() async {
        let started = expectation(description: "indexing child started")
        let task = Task {
            try await VideoFrameTimeline.runStructuredIndexing {
                started.fulfill()
                while true {
                    try Task.checkCancellation()
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
        }

        await fulfillment(of: [started], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled indexing unexpectedly returned")
        } catch is CancellationError {
            // Expected: cancellation reached and tore down the child task.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
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

    func testSixtyFPSFixtureHasExactSampleCount() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "test_60fps_5s", withExtension: "mp4"))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let nominalRate = try await Double(track.load(.nominalFrameRate))

        let timeline = try await VideoFrameTimeline.load(
            asset: asset,
            track: track,
            nominalFrameRate: nominalRate
        )

        XCTAssertEqual(timeline.count, 300)
        XCTAssertEqual(timeline.nominalFrameRate, 60, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(timeline.time(forFrame: 0)), 0, accuracy: 0.000_001)
    }

    func testTwentyThreeNineSevenSixFixtureHasExactSampleCount() async throws {
        let timeline = try await loadFixture(named: "test_23976fps_24f")

        XCTAssertEqual(timeline.precision, .exact)
        XCTAssertEqual(timeline.count, 24)
        XCTAssertEqual(timeline.nominalFrameRate, 24_000.0 / 1_001.0, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(timeline.time(forFrame: 0)), 0, accuracy: 0.000_001)
        XCTAssertEqual(
            CMTimeGetSeconds(timeline.time(forFrame: 23)),
            23 * 1_001.0 / 24_000.0,
            accuracy: 0.000_01
        )
    }

    func testFiftyNineNineFourFixtureHasExactSampleCount() async throws {
        let timeline = try await loadFixture(named: "test_5994fps_60f")

        XCTAssertEqual(timeline.precision, .exact)
        XCTAssertEqual(timeline.count, 60)
        XCTAssertEqual(timeline.nominalFrameRate, 60_000.0 / 1_001.0, accuracy: 0.001)
        XCTAssertEqual(
            CMTimeGetSeconds(timeline.time(forFrame: 59)),
            59 * 1_001.0 / 60_000.0,
            accuracy: 0.000_01
        )
    }

    func testRealVariableFrameRateFixturePreservesIrregularPresentationIntervals() async throws {
        let timeline = try await loadFixture(named: "test_vfr_11f")

        XCTAssertEqual(timeline.precision, .exact)
        XCTAssertEqual(timeline.count, 11)
        let intervals = (1..<timeline.count).map {
            CMTimeGetSeconds(
                CMTimeSubtract(
                    timeline.time(forFrame: $0),
                    timeline.time(forFrame: $0 - 1)
                )
            )
        }
        XCTAssertTrue(intervals.prefix(5).allSatisfy { abs($0 - 0.1) < 0.000_01 })
        XCTAssertTrue(intervals.suffix(5).allSatisfy { abs($0 - 0.05) < 0.000_01 })
        XCTAssertEqual(
            timeline.nearestFrameIndex(
                to: CMTime(seconds: 0.574, preferredTimescale: 60_000)
            ),
            6
        )
        XCTAssertEqual(
            timeline.nearestFrameIndex(
                to: CMTime(seconds: 0.576, preferredTimescale: 60_000)
            ),
            7
        )
    }

    private func loadFixture(named name: String) async throws -> VideoFrameTimeline {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "mp4"))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let nominalRate = try await Double(track.load(.nominalFrameRate))
        return try await VideoFrameTimeline.load(
            asset: asset,
            track: track,
            nominalFrameRate: nominalRate
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

final class SecurityScopedURLLeaseTests: XCTestCase {
    func testSuccessfulStartStopsExactlyOnceAfterFinalReference() {
        let events = LockedEventRecorder()
        let url = URL(fileURLWithPath: "/tmp/reframer-lease-success.mov")
        let access = SecurityScopedURLAccess(
            start: {
                events.append("start:\($0.lastPathComponent)")
                return true
            },
            stop: {
                events.append("stop:\($0.lastPathComponent)")
            }
        )

        var owner: SecurityScopedURLLease? = SecurityScopedURLLease(
            url: url,
            access: access
        )
        weak let weakLease = owner
        var asyncOwner = owner

        XCTAssertNotNil(asyncOwner)
        owner = nil
        XCTAssertNotNil(weakLease)
        XCTAssertEqual(events.snapshot(), ["start:reframer-lease-success.mov"])

        asyncOwner = nil
        XCTAssertNil(weakLease)
        XCTAssertEqual(
            events.snapshot(),
            [
                "start:reframer-lease-success.mov",
                "stop:reframer-lease-success.mov"
            ]
        )
    }

    func testFailedStartNeverCallsStop() {
        let events = LockedEventRecorder()
        var lease: SecurityScopedURLLease? = SecurityScopedURLLease(
            url: URL(fileURLWithPath: "/tmp/reframer-lease-denied.mov"),
            access: SecurityScopedURLAccess(
                start: { _ in
                    events.append("start")
                    return false
                },
                stop: { _ in events.append("stop") }
            )
        )

        XCTAssertNotNil(lease)
        lease = nil

        XCTAssertEqual(events.snapshot(), ["start"])
    }
}

@MainActor
final class VideoViewLifecycleTests: XCTestCase {
    func testMOVAndM4VFixturesReachReadyPlaybackState() async throws {
        let bundle = Bundle(for: Self.self)

        for fileExtension in ["mov", "m4v"] {
            let suiteName =
                "Reframer.VideoViewLifecycleTests.\(fileExtension).\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let url = try XCTUnwrap(
                bundle.url(
                    forResource: "test_playable",
                    withExtension: fileExtension
                )
            )
            let state = VideoState(defaults: defaults)
            let videoView = VideoView(
                frame: NSRect(x: 0, y: 0, width: 640, height: 480)
            )
            videoView.videoState = state

            state.videoURL = url
            let loaded = await waitUntil(timeout: 5) {
                state.isVideoLoaded
                    && state.frameNavigationPrecision == .exact
            }

            XCTAssertTrue(
                loaded,
                state.videoErrorMessage
                    ?? "\(fileExtension.uppercased()) did not reach ready state"
            )
            XCTAssertEqual(state.totalFrames, 6)
            XCTAssertEqual(
                state.videoNaturalSize.width / state.videoNaturalSize.height,
                1,
                accuracy: 0.001
            )
            XCTAssertFalse(state.isPlaying)
            state.videoURL = nil
        }
    }

    func testSecondLoadSupersedesFirstWithoutStaleMetadataWinning() async throws {
        let suiteName = "Reframer.VideoViewLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundle = Bundle(for: Self.self)
        let firstURL = try XCTUnwrap(
            bundle.url(forResource: "test-video", withExtension: "mp4")
        )
        let secondURL = try XCTUnwrap(
            bundle.url(forResource: "test_4x3_1s", withExtension: "mp4")
        )
        let state = VideoState(defaults: defaults)
        let videoView = VideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        videoView.videoState = state

        state.videoURL = firstURL
        let firstStarted = await waitUntil {
            state.isVideoLoading || state.isVideoLoaded
        }
        XCTAssertTrue(firstStarted)

        state.videoURL = secondURL
        let secondFinished = await waitUntil(timeout: 5) {
            state.isVideoLoaded
                && state.frameNavigationPrecision == .exact
                && abs(state.videoNaturalSize.width / state.videoNaturalSize.height - (4.0 / 3.0)) < 0.001
        }
        XCTAssertTrue(secondFinished, state.videoErrorMessage ?? "Second video did not finish loading")

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.videoURL, secondURL)
        XCTAssertEqual(state.duration, 1, accuracy: 0.05)
        XCTAssertEqual(
            state.videoNaturalSize.width / state.videoNaturalSize.height,
            4.0 / 3.0,
            accuracy: 0.001
        )
        XCTAssertNil(state.videoErrorMessage)
    }

    func testReplacingPlayingVideoEntersLoadingAndLandsPaused() async throws {
        let suiteName = "Reframer.VideoViewLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundle = Bundle(for: Self.self)
        let firstURL = try XCTUnwrap(
            bundle.url(forResource: "test_30fps_2s", withExtension: "mp4")
        )
        let secondURL = try XCTUnwrap(
            bundle.url(forResource: "test_4x3_1s", withExtension: "mp4")
        )
        let state = VideoState(defaults: defaults)
        let videoView = VideoView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )
        videoView.videoState = state

        state.videoURL = firstURL
        let firstLoaded = await waitUntil(timeout: 5) {
            state.isVideoLoaded
                && state.frameNavigationPrecision == .exact
        }
        XCTAssertTrue(
            firstLoaded,
            state.videoErrorMessage ?? "First video did not finish loading"
        )

        state.isPlaying = true
        XCTAssertTrue(state.isPlaying)

        let replacementGate = AsyncTestGate()
        videoView.loadEnvironment = VideoLoadEnvironment(
            securityScopedAccess: VideoLoadEnvironment.live.securityScopedAccess,
            preflight: { url in
                if url.standardizedFileURL == secondURL.standardizedFileURL {
                    await replacementGate.wait()
                }
                return try await VideoFormats.preflight(url)
            },
            loadTimeline: VideoLoadEnvironment.live.loadTimeline
        )

        state.videoURL = secondURL
        let replacementLoading = await waitUntil {
            state.isVideoLoading && !state.isVideoLoaded
        }
        XCTAssertTrue(replacementLoading)
        XCTAssertFalse(
            state.isPlaying,
            "Loading state must not retain the prior player's playing state"
        )

        await replacementGate.open()
        let replacementLoaded = await waitUntil(timeout: 5) {
            state.isVideoLoaded
                && state.frameNavigationPrecision == .exact
        }
        XCTAssertTrue(
            replacementLoaded,
            state.videoErrorMessage ?? "Replacement video did not finish loading"
        )
        XCTAssertFalse(
            state.isPlaying,
            "A newly selected replacement must land paused"
        )
        state.videoURL = nil
    }

    func testUnloadCancelsInFlightLoadAndPreventsLateReadiness() async throws {
        let suiteName = "Reframer.VideoViewLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "test-video", withExtension: "mp4")
        )
        let state = VideoState(defaults: defaults)
        let videoView = VideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        videoView.videoState = state

        state.videoURL = url
        let started = await waitUntil {
            state.isVideoLoading || state.isVideoLoaded
        }
        XCTAssertTrue(started)

        state.videoURL = nil
        let unloaded = await waitUntil {
            !state.isVideoLoading
                && !state.isVideoLoaded
                && state.frameNavigationPrecision == .unavailable
        }
        XCTAssertTrue(unloaded)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(state.isVideoLoaded)
        XCTAssertFalse(state.isVideoLoading)
        XCTAssertEqual(state.duration, 0)
        XCTAssertEqual(state.totalFrames, 0)
        XCTAssertNil(state.videoErrorMessage)
        XCTAssertFalse(state.isScrubbing)
    }

    func testSupersededBlockedLoadAcquiresReplacementBeforeOldLeaseReleases() async throws {
        let suiteName = "Reframer.VideoViewLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundle = Bundle(for: Self.self)
        let firstURL = try XCTUnwrap(
            bundle.url(forResource: "test-video", withExtension: "mp4")
        )
        let secondURL = try XCTUnwrap(
            bundle.url(forResource: "test_4x3_1s", withExtension: "mp4")
        )
        let firstGate = AsyncTestGate()
        let secondGate = AsyncTestGate()
        let events = LockedEventRecorder()
        let state = VideoState(defaults: defaults)
        let videoView = VideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        videoView.loadEnvironment = VideoLoadEnvironment(
            securityScopedAccess: SecurityScopedURLAccess(
                start: {
                    events.append("start:\($0.lastPathComponent)")
                    return true
                },
                stop: {
                    events.append("stop:\($0.lastPathComponent)")
                }
            ),
            preflight: { url in
                events.append("preflight:\(url.lastPathComponent)")
                if url.standardizedFileURL == firstURL.standardizedFileURL {
                    await firstGate.wait()
                } else {
                    await secondGate.wait()
                }
                return AVURLAsset(url: url)
            },
            loadTimeline: VideoLoadEnvironment.live.loadTimeline
        )
        videoView.videoState = state

        state.videoURL = firstURL
        let firstBlocked = await waitUntil {
            events.snapshot().contains("preflight:\(firstURL.lastPathComponent)")
        }
        XCTAssertTrue(firstBlocked)

        state.videoURL = secondURL
        let secondBlocked = await waitUntil {
            events.snapshot().contains("preflight:\(secondURL.lastPathComponent)")
        }
        XCTAssertTrue(secondBlocked)
        var snapshot = events.snapshot()
        XCTAssertFalse(snapshot.contains("stop:\(firstURL.lastPathComponent)"))
        XCTAssertLessThan(
            try XCTUnwrap(snapshot.firstIndex(of: "start:\(firstURL.lastPathComponent)")),
            try XCTUnwrap(snapshot.firstIndex(of: "start:\(secondURL.lastPathComponent)"))
        )

        await firstGate.open()
        let firstReleased = await waitUntil {
            events.snapshot().contains("stop:\(firstURL.lastPathComponent)")
        }
        XCTAssertTrue(firstReleased)
        snapshot = events.snapshot()
        XCTAssertLessThan(
            try XCTUnwrap(snapshot.firstIndex(of: "start:\(secondURL.lastPathComponent)")),
            try XCTUnwrap(snapshot.firstIndex(of: "stop:\(firstURL.lastPathComponent)"))
        )

        state.videoURL = nil
        let unloaded = await waitUntil { !state.isVideoLoading && !state.isVideoLoaded }
        XCTAssertTrue(unloaded)
        XCTAssertFalse(
            events.snapshot().contains("stop:\(secondURL.lastPathComponent)"),
            "Cancelling a task must not release its lease before it unwinds"
        )

        await secondGate.open()
        let secondReleased = await waitUntil {
            events.snapshot().contains("stop:\(secondURL.lastPathComponent)")
        }
        XCTAssertTrue(secondReleased)
        snapshot = events.snapshot()
        XCTAssertEqual(
            snapshot.filter { $0 == "stop:\(firstURL.lastPathComponent)" }.count,
            1
        )
        XCTAssertEqual(
            snapshot.filter { $0 == "stop:\(secondURL.lastPathComponent)" }.count,
            1
        )
    }

    func testSuccessfulUnloadTearsDownPlayerBeforeLeaseRelease() async throws {
        let suiteName = "Reframer.VideoViewLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "test_4x3_1s",
                withExtension: "mp4"
            )
        )
        let events = LockedEventRecorder()
        let state = VideoState(defaults: defaults)
        let videoView = VideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        videoView.loadEnvironment = VideoLoadEnvironment(
            securityScopedAccess: SecurityScopedURLAccess(
                start: { _ in
                    events.append("start")
                    return true
                },
                stop: { [weak videoView] _ in
                    MainActor.assumeIsolated {
                        events.append(
                            videoView?.hasActivePlaybackResources == true
                                ? "stop:player-active"
                                : "stop:player-torn-down"
                        )
                    }
                }
            ),
            preflight: VideoLoadEnvironment.live.preflight,
            loadTimeline: VideoLoadEnvironment.live.loadTimeline
        )
        videoView.videoState = state

        state.videoURL = url
        let loaded = await waitUntil(timeout: 5) {
            state.isVideoLoaded && state.frameNavigationPrecision == .exact
        }
        XCTAssertTrue(loaded)
        try await Task.sleep(nanoseconds: 50_000_000)

        state.videoURL = nil
        let stopped = await waitUntil {
            events.snapshot().contains("stop:player-torn-down")
        }
        XCTAssertTrue(stopped)
        XCTAssertFalse(events.snapshot().contains("stop:player-active"))
        XCTAssertEqual(events.snapshot().filter { $0.hasPrefix("stop:") }.count, 1)
    }

    func testDelayedExactIndexPromotionAndSampleCapFallbackAreDeterministic() async throws {
        let suiteName = "Reframer.VideoViewLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "test_4x3_1s",
                withExtension: "mp4"
            )
        )
        let gate = AsyncTestGate()
        let events = LockedEventRecorder()
        let state = VideoState(defaults: defaults)
        let videoView = VideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        videoView.loadEnvironment = VideoLoadEnvironment(
            securityScopedAccess: SecurityScopedURLAccess(
                start: { _ in false },
                stop: { _ in XCTFail("A failed scope start must not be stopped") }
            ),
            preflight: VideoLoadEnvironment.live.preflight,
            loadTimeline: { _, _, _ in
                events.append("exact-index-started")
                await gate.wait()
                return VideoFrameTimeline(
                    presentationTimes: [0, 0.2, 0.55, 0.9].map {
                        CMTime(seconds: $0, preferredTimescale: 10_000)
                    },
                    nominalFrameRate: 0
                )
            }
        )
        videoView.videoState = state

        state.videoURL = url
        let indexing = await waitUntil(timeout: 5) {
            state.isVideoLoaded
                && state.frameNavigationPrecision == .indexing
                && events.snapshot().contains("exact-index-started")
        }
        XCTAssertTrue(indexing)
        await gate.open()
        let promoted = await waitUntil {
            state.frameNavigationPrecision == .exact && state.totalFrames == 4
        }
        XCTAssertTrue(promoted)

        videoView.loadEnvironment = VideoLoadEnvironment(
            securityScopedAccess: videoView.loadEnvironment.securityScopedAccess,
            preflight: VideoLoadEnvironment.live.preflight,
            loadTimeline: { _, _, _ in
                throw VideoFrameTimelineError.exactSampleLimitExceeded(
                    maximum: VideoFrameTimeline.maximumExactSampleCount
                )
            }
        )
        videoView.loadVideo(url: url)
        let fellBack = await waitUntil(timeout: 5) {
            state.isVideoLoaded && state.frameNavigationPrecision == .estimated
        }
        XCTAssertTrue(fellBack)
        XCTAssertGreaterThan(state.totalFrames, 0)
        XCTAssertNil(state.videoErrorMessage)
        XCTAssertTrue(state.frameNavigationPrecision.supportsFrameNavigation)
        XCTAssertNotNil(state.frameNavigationMessage)
        state.videoURL = nil
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                return false
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }
}

private final class LockedEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private actor AsyncTestGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
