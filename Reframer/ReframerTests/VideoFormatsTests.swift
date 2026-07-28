import AVFoundation
import XCTest
import UniformTypeIdentifiers
@testable import Reframer

final class VideoFormatsTests: XCTestCase {

    // MARK: - F-VP-001: Supported Video Formats

    func testMP4Supported() {
        XCTAssertTrue(VideoFormats.supportedExtensions.contains("mp4"),
                      "MP4 should be a supported format")
    }

    func testMOVSupported() {
        XCTAssertTrue(VideoFormats.supportedExtensions.contains("mov"),
                      "MOV should be a supported format")
    }

    func testM4VSupported() {
        XCTAssertTrue(VideoFormats.supportedExtensions.contains("m4v"),
                      "M4V should be a supported format")
    }

    func testAVIIsNotAdvertisedOrAccepted() {
        XCTAssertFalse(VideoFormats.supportedExtensions.contains("avi"))
        XCTAssertFalse(VideoFormats.isSupported(URL(fileURLWithPath: "/test/video.avi")))
    }

    func testSupportedTypesNotEmpty() {
        XCTAssertFalse(VideoFormats.supportedTypes.isEmpty, "There should be supported types")
        XCTAssertGreaterThanOrEqual(VideoFormats.supportedTypes.count, 2)
    }

    func testSupportedExtensionsNotEmpty() {
        XCTAssertFalse(VideoFormats.supportedExtensions.isEmpty, "Should have supported extensions")
        XCTAssertEqual(VideoFormats.supportedExtensions, ["mp4", "m4v", "mov"])
    }

    // MARK: - isSupported URL method

    func testIsSupportedWithMP4URL() {
        let url = URL(fileURLWithPath: "/test/video.mp4")
        XCTAssertTrue(VideoFormats.isSupported(url), "MP4 URL should be supported")
    }

    func testIsSupportedWithMOVURL() {
        let url = URL(fileURLWithPath: "/test/video.mov")
        XCTAssertTrue(VideoFormats.isSupported(url), "MOV URL should be supported")
    }

    func testIsSupportedWithUnsupportedURL() {
        let url = URL(fileURLWithPath: "/test/image.png")
        XCTAssertFalse(VideoFormats.isSupported(url), "PNG URL should not be supported")
    }

    func testIsSupportedCaseInsensitive() {
        let url = URL(fileURLWithPath: "/test/video.MP4")
        XCTAssertTrue(VideoFormats.isSupported(url), "Extensions should be case-insensitive")
    }

    func testIsSupportedWithContentType() {
        XCTAssertTrue(VideoFormats.isSupported(contentType: .mpeg4Movie), "MPEG4 content type should be supported")
        XCTAssertFalse(VideoFormats.isSupported(contentType: .movie), "A generic movie claim would exceed the product contract")
    }

    func testTrackSelectionPrefersEnabledUsableTrack() {
        let candidates = [
            VideoTrackSelectionCandidate(
                isEnabled: false,
                isPlayable: true,
                isDecodable: true,
                hasSamples: true,
                displaySize: CGSize(width: 640, height: 480)
            ),
            VideoTrackSelectionCandidate(
                isEnabled: true,
                isPlayable: true,
                isDecodable: true,
                hasSamples: true,
                displaySize: CGSize(width: 1920, height: 1080)
            )
        ]

        XCTAssertEqual(
            VideoFormats.preferredVideoTrackIndex(in: candidates),
            1
        )
    }

    func testTrackSelectionSkipsInvalidEnabledTrackAndUsesUsableFallback() {
        let candidates = [
            VideoTrackSelectionCandidate(
                isEnabled: true,
                isPlayable: true,
                isDecodable: true,
                hasSamples: false,
                displaySize: CGSize(width: 1920, height: 1080)
            ),
            VideoTrackSelectionCandidate(
                isEnabled: false,
                isPlayable: true,
                isDecodable: true,
                hasSamples: true,
                displaySize: CGSize(width: 640, height: 480)
            )
        ]

        XCTAssertEqual(
            VideoFormats.preferredVideoTrackIndex(in: candidates),
            1
        )
    }

    func testTrackSelectionRejectsNonFiniteOrUndecodableCandidates() {
        let candidates = [
            VideoTrackSelectionCandidate(
                isEnabled: true,
                isPlayable: true,
                isDecodable: false,
                hasSamples: true,
                displaySize: CGSize(width: 640, height: 480)
            ),
            VideoTrackSelectionCandidate(
                isEnabled: true,
                isPlayable: true,
                isDecodable: true,
                hasSamples: true,
                displaySize: CGSize(width: CGFloat.infinity, height: 480)
            )
        ]

        XCTAssertNil(VideoFormats.preferredVideoTrackIndex(in: candidates))
    }

    func testDisplaySizeUsesTransformedRectangleBounds() {
        let displaySize = VideoFormats.displaySize(
            naturalSize: CGSize(width: 100, height: 100),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 4)
        )

        XCTAssertEqual(displaySize.width, 141.421, accuracy: 0.001)
        XCTAssertEqual(displaySize.height, 141.421, accuracy: 0.001)
    }

    // MARK: - UTType support

    func testMPEG4MovieTypeSupported() {
        XCTAssertTrue(VideoFormats.supportedTypes.contains(.mpeg4Movie),
                      "MPEG4 movie type should be supported")
    }

    func testQuickTimeMovieTypeSupported() {
        XCTAssertTrue(VideoFormats.supportedTypes.contains(.quickTimeMovie),
                      "QuickTime movie type should be supported")
    }

    func testAVITypeIsNotSupported() {
        XCTAssertFalse(VideoFormats.isSupported(contentType: .avi))
    }

    // MARK: - Display String

    func testDisplayStringNotEmpty() {
        XCTAssertFalse(VideoFormats.displayString.isEmpty, "Display string should not be empty")
        XCTAssertTrue(VideoFormats.displayString.contains("MP4"), "Display string should mention MP4")
        XCTAssertTrue(VideoFormats.displayString.contains("M4V"))
        XCTAssertTrue(VideoFormats.displayString.contains("MOV"))
    }

    func testPreflightAcceptsKnownFixture() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "test_30fps_2s", withExtension: "mp4"))

        let asset = try await VideoFormats.preflight(url)
        let tracks = try await asset.loadTracks(withMediaType: .video)

        XCTAssertFalse(tracks.isEmpty)
    }

    func testPreflightAcceptsPlayableMOVFixture() async throws {
        try await assertPreflightAcceptsPlayableFixture(
            named: "test_playable",
            extension: "mov"
        )
    }

    func testPreflightAcceptsPlayableM4VFixture() async throws {
        try await assertPreflightAcceptsPlayableFixture(
            named: "test_playable",
            extension: "m4v"
        )
    }

    func testSelectedFixtureTrackIsEnabledUsableAndCoherent() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "test_30fps_2s",
                withExtension: "mp4"
            )
        )
        let asset = try await VideoFormats.preflight(url)

        let selected = try await VideoFormats.selectVideoTrack(in: asset)
        let isEnabled = try await selected.track.load(.isEnabled)
        let isPlayable = try await selected.track.load(.isPlayable)
        let isDecodable = try await selected.track.load(.isDecodable)

        XCTAssertTrue(isEnabled)
        XCTAssertTrue(isPlayable)
        XCTAssertTrue(isDecodable)
        XCTAssertGreaterThan(selected.displaySize.width, 0)
        XCTAssertGreaterThan(selected.displaySize.height, 0)
        XCTAssertEqual(selected.trackID, selected.track.trackID)
    }

    func testPreparedPlaybackAssetUsesOnlySelectedVideoTrackAndPreservesAudio() async throws {
        let bundle = Bundle(for: Self.self)
        let videoURL = try XCTUnwrap(
            bundle.url(forResource: "test_30fps_2s", withExtension: "mp4")
        )
        let selectedVideoURL = try XCTUnwrap(
            bundle.url(forResource: "test_4x3_1s", withExtension: "mp4")
        )
        let audioURL = try XCTUnwrap(
            bundle.url(forResource: "test_audio_only", withExtension: "mp4")
        )
        let videoAsset = AVURLAsset(url: videoURL)
        let selectedVideoAsset = AVURLAsset(url: selectedVideoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let fixtureVideoTracks = try await videoAsset.loadTracks(
            withMediaType: .video
        )
        let selectedFixtureVideoTracks = try await selectedVideoAsset.loadTracks(
            withMediaType: .video
        )
        let fixtureAudioTracks = try await audioAsset.loadTracks(
            withMediaType: .audio
        )
        let fixtureVideoTrack = try XCTUnwrap(
            fixtureVideoTracks.first
        )
        let selectedFixtureVideoTrack = try XCTUnwrap(
            selectedFixtureVideoTracks.first
        )
        let fixtureAudioTrack = try XCTUnwrap(
            fixtureAudioTracks.first
        )
        let videoTimeRange = try await fixtureVideoTrack.load(.timeRange)
        let selectedVideoTimeRange = try await selectedFixtureVideoTrack.load(
            .timeRange
        )
        let audioTimeRange = try await fixtureAudioTrack.load(.timeRange)
        let preferredTransform = try await selectedFixtureVideoTrack.load(
            .preferredTransform
        )
        let naturalSize = try await selectedFixtureVideoTrack.load(.naturalSize)
        let nominalFrameRate = try await selectedFixtureVideoTrack.load(
            .nominalFrameRate
        )

        let adversarialAsset = AVMutableComposition()
        let firstEnabledVideoTrack = try XCTUnwrap(
            adversarialAsset.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        )
        try firstEnabledVideoTrack.insertTimeRange(
            videoTimeRange,
            of: fixtureVideoTrack,
            at: .zero
        )
        firstEnabledVideoTrack.isEnabled = true

        let selectedDisabledVideoTrack = try XCTUnwrap(
            adversarialAsset.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        )
        try selectedDisabledVideoTrack.insertTimeRange(
            selectedVideoTimeRange,
            of: selectedFixtureVideoTrack,
            at: .zero
        )
        selectedDisabledVideoTrack.preferredTransform = preferredTransform
        selectedDisabledVideoTrack.isEnabled = false

        let sourceAudioTrack = try XCTUnwrap(
            adversarialAsset.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        )
        for index in 0..<10 {
            try sourceAudioTrack.insertTimeRange(
                audioTimeRange,
                of: fixtureAudioTrack,
                at: CMTimeMultiply(
                    audioTimeRange.duration,
                    multiplier: Int32(index)
                )
            )
        }
        sourceAudioTrack.preferredVolume = 0.375
        sourceAudioTrack.languageCode = "eng"
        sourceAudioTrack.isEnabled = true

        let selected = SelectedVideoTrack(
            track: selectedDisabledVideoTrack,
            trackID: selectedDisabledVideoTrack.trackID,
            nominalFrameRate: Double(nominalFrameRate),
            displaySize: VideoFormats.displaySize(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform
            )
        )

        let prepared = try await VideoFormats.preparePlaybackAsset(
            from: adversarialAsset,
            selectedVideoTrack: selected
        )
        let preparedVideoTracks = try await prepared.asset.loadTracks(
            withMediaType: .video
        )
        let preparedVideoTrack = try XCTUnwrap(preparedVideoTracks.first)
        let preparedVideoSegments = try await preparedVideoTrack.load(.segments)
        let preparedVideoIsEnabled = try await preparedVideoTrack.load(.isEnabled)
        let preparedVideoTransform = try await preparedVideoTrack.load(
            .preferredTransform
        )
        let preparedVideoTimeRange = try await preparedVideoTrack.load(.timeRange)
        let selectedCompositionVideoTimeRange = try await selectedDisabledVideoTrack.load(
            .timeRange
        )
        let firstEnabledVideoTimeRange = try await firstEnabledVideoTrack.load(
            .timeRange
        )

        XCTAssertEqual(preparedVideoTracks.count, 1)
        XCTAssertEqual(preparedVideoTrack.trackID, prepared.selectedVideoTrackID)
        XCTAssertTrue(preparedVideoIsEnabled)
        XCTAssertTrue(preparedVideoSegments.contains(where: { !$0.isEmpty }))
        XCTAssertEqual(preparedVideoTransform, preferredTransform)
        XCTAssertEqual(
            preparedVideoTimeRange,
            selectedCompositionVideoTimeRange
        )
        XCTAssertNotEqual(
            preparedVideoTimeRange,
            firstEnabledVideoTimeRange
        )

        let preparedAudioTracks = try await prepared.asset.loadTracks(
            withMediaType: .audio
        )
        let preparedAudioTrack = try XCTUnwrap(preparedAudioTracks.first)
        let preparedAudioSegments = try await preparedAudioTrack.load(.segments)
        let preparedAudioVolume = try await preparedAudioTrack.load(
            .preferredVolume
        )
        let preparedAudioLanguageCode = try await preparedAudioTrack.load(
            .languageCode
        )
        let preparedAudioTimeRange = try await preparedAudioTrack.load(.timeRange)
        let sourceAudioTimeRange = try await sourceAudioTrack.load(.timeRange)
        let preparedDuration = try await prepared.asset.load(.duration)
        XCTAssertEqual(preparedAudioTracks.count, 1)
        XCTAssertTrue(preparedAudioSegments.contains(where: { !$0.isEmpty }))
        XCTAssertGreaterThan(
            CMTimeCompare(
                sourceAudioTimeRange.duration,
                selectedCompositionVideoTimeRange.duration
            ),
            0,
            "The adversarial source audio must outlast the selected video"
        )
        XCTAssertEqual(
            preparedAudioTimeRange,
            CMTimeRangeGetIntersection(
                sourceAudioTimeRange,
                otherRange: selectedCompositionVideoTimeRange
            )
        )
        XCTAssertEqual(
            preparedDuration,
            CMTimeRangeGetEnd(selectedCompositionVideoTimeRange)
        )
        XCTAssertEqual(preparedAudioVolume, 0.375, accuracy: 0.001)
        XCTAssertEqual(preparedAudioLanguageCode, "eng")

        let filterComposition = try await makePassthroughFilterComposition(
            for: prepared.asset
        )
        XCTAssertEqual(
            filterComposition.renderSize.width,
            selected.displaySize.width,
            accuracy: 0.001
        )
        XCTAssertEqual(
            filterComposition.renderSize.height,
            selected.displaySize.height,
            accuracy: 0.001
        )
    }

    func testPreflightRejectsMissingSupportedFile() async {
        do {
            _ = try await VideoFormats.preflight(
                URL(fileURLWithPath: "/tmp/reframer-missing-fixture.mp4")
            )
            XCTFail("Preflight should reject a missing file")
        } catch let error as VideoPreflightError {
            guard case .missingFile = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreflightRejectsCorruptDataWithSupportedExtension() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reframer-corrupt-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        try Data("not a QuickTime movie".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await VideoFormats.preflight(url)
            XCTFail("Preflight should reject corrupt data even when the extension is supported")
        } catch let error as VideoPreflightError {
            guard case .notPlayable = error else {
                return XCTFail("Unexpected preflight error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPreflightRejectsValidAudioOnlyMP4() async throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "test_audio_only", withExtension: "mp4")
        )

        do {
            _ = try await VideoFormats.preflight(url)
            XCTFail("Preflight should reject a valid MP4 container without a video track")
        } catch let error as VideoPreflightError {
            guard case .noVideoTrack = error else {
                return XCTFail("Unexpected preflight error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func assertPreflightAcceptsPlayableFixture(
        named name: String,
        extension fileExtension: String
    ) async throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: name,
                withExtension: fileExtension
            )
        )

        let asset = try await VideoFormats.preflight(url)
        let selectedTrack = try await VideoFormats.selectVideoTrack(in: asset)
        let isPlayable = try await selectedTrack.track.load(.isPlayable)
        let isDecodable = try await selectedTrack.track.load(.isDecodable)

        XCTAssertTrue(isPlayable)
        XCTAssertTrue(isDecodable)
        XCTAssertGreaterThan(selectedTrack.displaySize.width, 0)
        XCTAssertGreaterThan(selectedTrack.displaySize.height, 0)
    }

    private func makePassthroughFilterComposition(
        for asset: AVAsset
    ) async throws -> AVVideoComposition {
        try await withCheckedThrowingContinuation { continuation in
            AVVideoComposition.videoComposition(
                with: asset,
                applyingCIFiltersWithHandler: { request in
                    request.finish(
                        with: request.sourceImage,
                        context: nil
                    )
                },
                completionHandler: { composition, error in
                    if let composition {
                        continuation.resume(returning: composition)
                    } else {
                        continuation.resume(
                            throwing: error
                                ?? VideoPreflightError.playbackTrackUnavailable
                        )
                    }
                }
            )
        }
    }
}
