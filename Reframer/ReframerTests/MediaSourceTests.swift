import Foundation
import AVFoundation
import AudioToolbox
import CoreGraphics
import WebKit
import XCTest
@testable import Reframer

final class YouTubeVideoReferenceTests: XCTestCase {
    private let videoID = "dQw4w9WgXcQ"

    func testAcceptsSupportedYouTubeURLFormsAndCanonicalizesThem() {
        let acceptedInputs = [
            "https://www.youtube.com/watch?v=\(videoID)",
            "youtube.com/watch?v=\(videoID)&t=42",
            "https://m.youtube.com/watch?v=\(videoID)",
            "https://music.youtube.com/watch?v=\(videoID)",
            "https://youtu.be/\(videoID)",
            "https://www.youtube.com/shorts/\(videoID)",
            "https://www.youtube.com/embed/\(videoID)",
            "https://www.youtube.com/live/\(videoID)",
            "https://www.youtube-nocookie.com/embed/\(videoID)"
        ]

        for input in acceptedInputs {
            let reference = YouTubeVideoReference.parse(input)
            XCTAssertEqual(reference?.videoID, videoID, input)
            XCTAssertEqual(
                reference?.canonicalURL.absoluteString,
                "https://www.youtube.com/watch?v=\(videoID)",
                input
            )
        }
    }

    func testTrimsWhitespaceAndAcceptsCaseInsensitiveHostAndQueryName() {
        let reference = YouTubeVideoReference.parse(
            " \nHTTPS://WWW.YOUTUBE.COM/watch?V=\(videoID)\t"
        )

        XCTAssertEqual(reference?.videoID, videoID)
    }

    func testRejectsNonHTTPSAmbiguousAndSpoofedURLs() {
        let rejectedInputs = [
            "",
            "http://www.youtube.com/watch?v=\(videoID)",
            "javascript:alert(1)",
            "https://youtube.com.evil.example/watch?v=\(videoID)",
            "https://www.youtube.com:443/watch?v=\(videoID)",
            "https://user@www.youtube.com/watch?v=\(videoID)",
            "https://www.youtube.com/watch?v=\(videoID)&v=\(videoID)",
            "https://youtu.be/\(videoID)/extra",
            "https://www.youtube.com/watch/extra?v=\(videoID)",
            "https://www.youtube.com/playlist?list=\(videoID)",
            "https://www.youtube.com/watch?v=too-short",
            "https://www.youtube.com/watch?v=dQw4w9WgXc!",
            "https://vimeo.com/\(videoID)"
        ]

        for input in rejectedInputs {
            XCTAssertNil(YouTubeVideoReference.parse(input), input)
        }
    }

    func testRejectsDecodedOrNonASCIIVideoIDCharacters() {
        XCTAssertNil(
            YouTubeVideoReference.parse(
                "https://youtu.be/abcdefghij%2F"
            )
        )
        XCTAssertNil(
            YouTubeVideoReference.parse(
                "https://youtu.be/abcdefghijé"
            )
        )
    }
}

final class WebMediaHTMLTests: XCTestCase {
    private let videoID = "dQw4w9WgXcQ"

    func testEmbedUsesPrivacyEnhancedPlayerWithRequiredIdentityAndControls() {
        let html = WebMediaHTML.youtube(
            videoID: videoID,
            token: "test-token"
        )

        XCTAssertEqual(
            WebMediaHTML.youtubeBaseURL.absoluteString,
            "https://com.reframer.app/"
        )
        XCTAssertTrue(
            html.contains(
                "https://www.youtube-nocookie.com/embed/\(videoID)"
            )
        )
        XCTAssertTrue(html.contains("enablejsapi=1"))
        XCTAssertTrue(
            html.contains("origin=https%3A%2F%2Fcom.reframer.app")
        )
        XCTAssertTrue(html.contains("autoplay=0"))
        XCTAssertTrue(html.contains("controls=1"))
        XCTAssertTrue(html.contains("playsinline=1"))
        XCTAssertTrue(html.contains("allowfullscreen"))
        XCTAssertTrue(
            html.contains(
                "referrerpolicy=\"strict-origin-when-cross-origin\""
            )
        )
        XCTAssertTrue(
            html.contains(
                "<meta name=\"referrer\" content=\"strict-origin-when-cross-origin\">"
            )
        )
        XCTAssertTrue(
            html.contains(
                "https://www.youtube.com/iframe_api"
            )
        )
    }

    func testEmbedDoesNotForceOrHideYouTubePlaybackQualityControls() {
        let html = WebMediaHTML.youtube(
            videoID: videoID,
            token: "test-token"
        )

        for forbiddenMarker in [
            "setPlaybackQuality",
            "getPlaybackQuality",
            "getAvailableQualityLevels",
            "suggestedQuality",
            "controls=0",
            "autoplay=1"
        ] {
            XCTAssertFalse(html.contains(forbiddenMarker), forbiddenMarker)
        }
        XCTAssertTrue(
            YouTubeVideoReference.qualityDisclosure.contains(
                "automatically selects the highest quality appropriate"
            )
        )
        XCTAssertTrue(
            YouTubeVideoReference.qualityDisclosure.contains(
                "does not let Reframer force a specific quality level"
            )
        )
    }

    func testEmbedUsesVersionedTokenedBridgeAndFourHertzPolling() {
        let html = WebMediaHTML.youtube(
            videoID: videoID,
            token: "bridge-token"
        )

        XCTAssertTrue(html.contains("const version = 1;"))
        XCTAssertTrue(html.contains("const token = \"bridge-token\";"))
        XCTAssertTrue(
            html.contains(
                "Object.assign({ version, type, token }, values)"
            )
        )
        XCTAssertTrue(html.contains("window.setInterval"))
        XCTAssertTrue(html.contains(", 250)"))
        XCTAssertTrue(html.contains("commandRevision"))
        XCTAssertTrue(html.contains("pendingRevision"))
        XCTAssertTrue(html.contains("volume: finite(player.getVolume()) / 100"))
        XCTAssertTrue(html.contains("muted: Boolean(player.isMuted())"))
        XCTAssertTrue(
            html.contains(
                "return [-1, 0, 2, 5].includes(playerState)"
            )
        )
    }

    func testSeekBridgeHonorsYouTubeScrubSeekAheadPolicy() {
        let html = WebMediaHTML.youtube(
            videoID: videoID,
            token: "seek-policy-token"
        )

        XCTAssertTrue(html.contains("seek(seconds, allowSeekAhead)"))
        XCTAssertTrue(
            html.contains(
                "Boolean(allowSeekAhead)"
            )
        )
        XCTAssertFalse(
            html.contains(
                "player.seekTo(Math.max(0, Math.min(duration, seconds)), true)"
            )
        )
    }

    func testMadeForKidsEmbedIsAuditableAndRemainsPrivacyEnhanced() {
        let html = WebMediaHTML.youtube(
            videoID: videoID,
            token: "child-directed-token",
            audience: .madeForKids
        )

        XCTAssertTrue(
            html.contains(
                "<meta name=\"reframer-audience\" content=\"made-for-kids\">"
            )
        )
        XCTAssertTrue(
            html.contains(
                "https://www.youtube-nocookie.com/embed/\(videoID)"
            )
        )
        XCTAssertFalse(html.contains("https://www.youtube.com/embed/"))
    }
}

final class WebMediaViewConfigurationTests: XCTestCase {
    @MainActor
    func testYouTubeHostEnablesElementFullscreen() throws {
        let view = WebMediaView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        defer { view.shutdown() }

        let webView = try XCTUnwrap(
            view.subviews.compactMap { $0 as? WKWebView }.first
        )
        XCTAssertTrue(
            webView.configuration.preferences.isElementFullscreenEnabled
        )
        XCTAssertTrue(
            webView.configuration.websiteDataStore.isPersistent == false
        )
    }

    @MainActor
    func testPlayerViewportUsesTheFullMinimumCanvas() throws {
        let view = WebMediaView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 200)
        )
        defer { view.shutdown() }
        view.layoutSubtreeIfNeeded()

        let webView = try XCTUnwrap(
            view.subviews.compactMap { $0 as? WKWebView }.first
        )
        XCTAssertEqual(webView.frame, view.bounds)
        XCTAssertGreaterThanOrEqual(webView.frame.width, 200)
        XCTAssertGreaterThanOrEqual(webView.frame.height, 200)
    }

    @MainActor
    func testPlayerTerminationInvalidatesGenerationBeforeLateMessages() throws {
        let suiteName = "Reframer.WebMediaFailureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = VideoState(defaults: defaults)
        let view = WebMediaView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        defer { view.shutdown() }
        view.beginPlaybackGenerationForTesting(token: "terminal-test")
        XCTAssertTrue(view.hasActivePlaybackGeneration)

        view.failPlaybackGenerationForTesting(
            "The test player stopped.",
            state: state
        )

        XCTAssertFalse(view.hasActivePlaybackGeneration)
        XCTAssertFalse(state.isVideoLoaded)
        XCTAssertFalse(state.isVideoLoading)
        XCTAssertNotNil(state.videoErrorMessage)
    }
}

final class WebMediaGenerationGateTests: XCTestCase {
    func testInvalidatedGenerationRejectsLateMessagesAndReplacementIsDistinct() {
        var gate = WebMediaGenerationGate()
        let expired = gate.begin(token: "expired")

        XCTAssertTrue(gate.accepts(expired))
        gate.invalidate()
        XCTAssertFalse(gate.accepts(expired))

        let replacement = gate.begin(token: "replacement")
        XCTAssertFalse(gate.accepts(expired))
        XCTAssertTrue(gate.accepts(replacement))
    }
}

final class LatestValueOperationGateTests: XCTestCase {
    func testInFlightOperationCoalescesToNewestPendingValue() {
        var gate = LatestValueOperationGate<String>()

        XCTAssertTrue(gate.submit("first"))
        XCTAssertFalse(gate.submit("second"))
        XCTAssertFalse(gate.submit("latest"))
        XCTAssertEqual(gate.complete(), "latest")
        XCTAssertFalse(gate.isRunning)

        XCTAssertTrue(gate.submit("next"))
        XCTAssertEqual(gate.complete(), "next")
    }

    func testCancellingPendingValueMakesLateCompletionInert() {
        var gate = LatestValueOperationGate<String>()

        XCTAssertTrue(gate.submit("obsolete"))
        gate.cancelPending()

        XCTAssertNil(gate.complete())
        XCTAssertFalse(gate.isRunning)
    }
}

final class WebMediaAudioReconciliationPolicyTests: XCTestCase {
    func testReadySnapshotCannotOverwriteSavedNativeAudio() {
        XCTAssertFalse(
            WebMediaAudioReconciliationPolicy.shouldReconcile(
                messageType: "ready"
            )
        )
        XCTAssertTrue(
            WebMediaAudioReconciliationPolicy.shouldReconcile(
                messageType: "time"
            )
        )
        XCTAssertTrue(
            WebMediaAudioReconciliationPolicy.shouldReconcile(
                messageType: "paused"
            )
        )
    }

    func testMutedDisplayedVolumeDoesNotErasePlayerUnmuteLevel() {
        XCTAssertFalse(
            WebMediaAudioReconciliationPolicy.shouldSetPlayerVolume(0)
        )
        XCTAssertTrue(
            WebMediaAudioReconciliationPolicy.shouldSetPlayerVolume(0.7)
        )
    }
}

final class WebMediaVisibilityPolicyTests: XCTestCase {
    func testVisibilityOnlyPausesAnActivelyPlayingYouTubeSource() {
        XCTAssertTrue(
            WebMediaVisibilityPolicy.shouldPause(
                isYouTube: true,
                isPlaying: true
            )
        )
        XCTAssertFalse(
            WebMediaVisibilityPolicy.shouldPause(
                isYouTube: true,
                isPlaying: false
            )
        )
        XCTAssertFalse(
            WebMediaVisibilityPolicy.shouldPause(
                isYouTube: false,
                isPlaying: true
            )
        )
    }
}

final class YouTubeComplianceClientTests: XCTestCase {
    private let videoID = "dQw4w9WgXcQ"

    override func tearDown() {
        YouTubeMockURLProtocol.removeHandler()
        super.tearDown()
    }

    func testMissingOrUnexpandedAPIKeyFailsClosedWithoutRequest() async {
        YouTubeMockURLProtocol.setHandler { _ in
            XCTFail("A missing API key must fail before issuing a request")
            throw URLError(.badURL)
        }
        let reference = try! XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/\(videoID)"
            )
        )

        let invalidKeys: [String?] = [
            nil,
            "",
            "   ",
            "$(YOUTUBE_DATA_API_KEY)",
            "${KEY}"
        ]
        for key in invalidKeys {
            let client = makeClient(apiKey: key)
            await assertAuthorizationFails(
                .missingAPIKey,
                client: client,
                reference: reference
            )
        }
    }

    func testSuccessfulCheckUsesExactVideoStatusRequestAndReturnsAudience() async throws {
        let requestRecorder = URLRequestRecorder()
        YouTubeMockURLProtocol.setHandler { request in
            requestRecorder.record(request)
            return Self.response(
                for: request,
                statusCode: 200,
                json: """
                {
                  "items": [{
                    "id": "\(self.videoID)",
                    "status": { "madeForKids": false }
                  }]
                }
                """
            )
        }
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://www.youtube.com/watch?v=\(videoID)"
            )
        )
        let authorization = try await makeClient(
            apiKey: "  unit-test-key  "
        ).authorize(reference)

        XCTAssertEqual(authorization.reference, reference)
        XCTAssertEqual(authorization.audience, .general)

        let request = try XCTUnwrap(requestRecorder.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "www.googleapis.com")
        XCTAssertEqual(request.url?.path, "/youtube/v3/videos")
        XCTAssertEqual(
            request.cachePolicy,
            .reloadIgnoringLocalCacheData
        )
        let queryItems = URLComponents(
            url: try XCTUnwrap(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        XCTAssertEqual(queryItems.value(named: "part"), "id,status")
        XCTAssertEqual(queryItems.value(named: "id"), videoID)
        XCTAssertNil(queryItems.value(named: "key"))
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Goog-Api-Key"),
            "unit-test-key"
        )
    }

    func testMadeForKidsResponseIsPreservedInAuthorization() async throws {
        YouTubeMockURLProtocol.setHandler { request in
            Self.response(
                for: request,
                statusCode: 200,
                json: """
                {
                  "items": [{
                    "id": "\(self.videoID)",
                    "status": { "madeForKids": true }
                  }]
                }
                """
            )
        }
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/\(videoID)"
            )
        )

        let authorization = try await makeClient(
            apiKey: "test-key"
        ).authorize(reference)

        XCTAssertEqual(authorization.audience, .madeForKids)
    }

    func testEveryEmbedAttemptPerformsANewAudienceRequest() async throws {
        let requestCount = LockedRequestCount()
        YouTubeMockURLProtocol.setHandler { request in
            requestCount.increment()
            return Self.response(
                for: request,
                statusCode: 200,
                json: """
                {
                  "items": [{
                    "id": "\(self.videoID)",
                    "status": { "madeForKids": false }
                  }]
                }
                """
            )
        }
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/\(videoID)"
            )
        )
        let client = makeClient(apiKey: "test-key")

        _ = try await client.authorize(reference)
        _ = try await client.authorize(reference)

        XCTAssertEqual(requestCount.value, 2)
    }

    func testNonSuccessHTTPResponseIsRejected() async throws {
        YouTubeMockURLProtocol.setHandler { request in
            Self.response(
                for: request,
                statusCode: 403,
                json: #"{"error":{"code":403}}"#
            )
        }
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/\(videoID)"
            )
        )

        await assertAuthorizationFails(
            .requestRejected,
            client: makeClient(apiKey: "test-key"),
            reference: reference
        )
    }

    func testMalformedResponseIsRejected() async throws {
        YouTubeMockURLProtocol.setHandler { request in
            Self.response(
                for: request,
                statusCode: 200,
                json: #"{"items":"not-an-array"}"#
            )
        }
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/\(videoID)"
            )
        )

        await assertAuthorizationFails(
            .invalidResponse,
            client: makeClient(apiKey: "test-key"),
            reference: reference
        )
    }

    func testMissingOrMismatchedVideoIsUnavailable() async throws {
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/\(videoID)"
            )
        )
        for json in [
            #"{"items":[]}"#,
            """
            {
              "items": [{
                "id": "aaaaaaaaaaa",
                "status": { "madeForKids": false }
              }]
            }
            """,
            """
            {
              "items": [
                {
                  "id": "\(videoID)",
                  "status": { "madeForKids": false }
                },
                {
                  "id": "aaaaaaaaaaa",
                  "status": { "madeForKids": false }
                }
              ]
            }
            """
        ] {
            YouTubeMockURLProtocol.setHandler { request in
                Self.response(
                    for: request,
                    statusCode: 200,
                    json: json
                )
            }
            await assertAuthorizationFails(
                .videoUnavailable,
                client: makeClient(apiKey: "test-key"),
                reference: reference
            )
        }
    }

    func testUnknownAudienceFailsClosed() async throws {
        YouTubeMockURLProtocol.setHandler { request in
            Self.response(
                for: request,
                statusCode: 200,
                json: """
                {
                  "items": [{
                    "id": "\(self.videoID)",
                    "status": {}
                  }]
                }
                """
            )
        }
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/\(videoID)"
            )
        )

        await assertAuthorizationFails(
            .audienceUnknown,
            client: makeClient(apiKey: "test-key"),
            reference: reference
        )
    }

    private func makeClient(apiKey: String?) -> YouTubeComplianceClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [YouTubeMockURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return YouTubeComplianceClient(
            apiKey: apiKey,
            session: URLSession(configuration: configuration)
        )
    }

    private func assertAuthorizationFails(
        _ expectedError: YouTubeComplianceError,
        client: YouTubeComplianceClient,
        reference: YouTubeVideoReference,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.authorize(reference)
            XCTFail(
                "Expected \(expectedError)",
                file: file,
                line: line
            )
        } catch let error as YouTubeComplianceError {
            XCTAssertEqual(
                error,
                expectedError,
                file: file,
                line: line
            )
        } catch {
            XCTFail(
                "Unexpected error: \(error)",
                file: file,
                line: line
            )
        }
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int,
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }
}

final class WebMProbeTests: XCTestCase {
    func testRecognizesVP8WithoutAlphaMetadata() throws {
        let url = try writeTemporaryWebM(
            tracks: [
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_VP8",
                    alphaMode: nil
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try WebMProbe.inspect(url),
            WebMProbeResult(codec: .vp8, hasAlpha: false)
        )
    }

    func testRecognizesVP9WithAlphaModeOne() throws {
        let url = try writeTemporaryWebM(
            tracks: [
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_VP9",
                    alphaMode: 1
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try WebMProbe.inspect(url),
            WebMProbeResult(codec: .vp9, hasAlpha: true)
        )
    }

    func testRecognizesTransparentVP8AlphaMode() throws {
        let url = try writeTemporaryWebM(
            tracks: [
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_VP8",
                    alphaMode: 1
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try WebMProbe.inspect(url),
            WebMProbeResult(codec: .vp8, hasAlpha: true)
        )
    }

    func testAlphaModeZeroDoesNotClaimTransparency() throws {
        let url = try writeTemporaryWebM(
            tracks: [
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_VP9",
                    alphaMode: 0
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try WebMProbe.inspect(url),
            WebMProbeResult(codec: .vp9, hasAlpha: false)
        )
    }

    func testSelectsFirstSupportedVideoTrackStructurally() throws {
        let url = try writeTemporaryWebM(
            tracks: [
                WebMTrackFixture(
                    type: 2,
                    codecID: "A_OPUS",
                    alphaMode: nil
                ),
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_VP8",
                    alphaMode: nil
                ),
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_VP9",
                    alphaMode: 1
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try WebMProbe.inspect(url),
            WebMProbeResult(codec: .vp8, hasAlpha: false)
        )
    }

    func testCarriesVideoStreamIndexPastUnsupportedVideoTracks() throws {
        let url = try writeTemporaryWebM(
            tracks: [
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_AV1",
                    alphaMode: nil
                ),
                WebMTrackFixture(
                    type: 2,
                    codecID: "A_OPUS",
                    alphaMode: nil
                ),
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_VP9",
                    alphaMode: 1
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try WebMProbe.inspect(url),
            WebMProbeResult(
                codec: .vp9,
                hasAlpha: true,
                videoStreamIndex: 1
            )
        )
    }

    func testRejectsInvalidContainerAndUnsupportedCodecSeparately() throws {
        let invalidContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("webm")
        var rawMarkers = Data("not a webm container V_VP9".utf8)
        rawMarkers.append(contentsOf: [0x53, 0xC0, 0x81, 0x01])
        try rawMarkers.write(
            to: invalidContainer,
            options: .atomic
        )
        defer { try? FileManager.default.removeItem(at: invalidContainer) }

        XCTAssertThrowsError(try WebMProbe.inspect(invalidContainer)) {
            XCTAssertEqual(
                $0 as? WebMPreparationError,
                .invalidContainer
            )
        }

        let unsupportedCodec = try writeTemporaryWebM(
            tracks: [
                WebMTrackFixture(
                    type: 1,
                    codecID: "V_AV1",
                    alphaMode: 1
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: unsupportedCodec) }

        XCTAssertThrowsError(try WebMProbe.inspect(unsupportedCodec)) {
            XCTAssertEqual(
                $0 as? WebMPreparationError,
                .unsupportedCodec
            )
        }
    }

    func testMissingInputReportsMissingInput() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("webm")

        XCTAssertThrowsError(try WebMProbe.inspect(missingURL)) {
            XCTAssertEqual(
                $0 as? WebMPreparationError,
                .missingInput
            )
        }
    }

    func testProbesRealTransparentWebMFixtures() throws {
        for (name, expected) in [
            (
                "test_vp8_alpha_vorbis",
                WebMProbeResult(codec: .vp8, hasAlpha: true)
            ),
            (
                "test_vp9_alpha_opus",
                WebMProbeResult(codec: .vp9, hasAlpha: true)
            ),
            (
                "test_vp9_alpha_no_audio",
                WebMProbeResult(codec: .vp9, hasAlpha: true)
            )
        ] {
            let url = try XCTUnwrap(
                Bundle(for: Self.self).url(
                    forResource: name,
                    withExtension: "webm"
                )
            )
            XCTAssertEqual(try WebMProbe.inspect(url), expected, name)
        }
    }

    private func writeTemporaryWebM(
        tracks: [WebMTrackFixture]
    ) throws -> URL {
        let docType = ebmlElement(
            id: [0x42, 0x82],
            payload: Data("webm".utf8)
        )
        let header = ebmlElement(
            id: [0x1A, 0x45, 0xDF, 0xA3],
            payload: docType
        )
        let trackEntries = tracks.reduce(into: Data()) { data, track in
            var entryPayload = Data()
            entryPayload.append(
                ebmlElement(
                    id: [0x83],
                    payload: Data([track.type])
                )
            )
            entryPayload.append(
                ebmlElement(
                    id: [0x86],
                    payload: Data(track.codecID.utf8)
                )
            )

            var videoPayload = Data()
            if let alphaMode = track.alphaMode {
                videoPayload.append(
                    ebmlElement(
                        id: [0x53, 0xC0],
                        payload: Data([alphaMode])
                    )
                )
            }
            entryPayload.append(
                ebmlElement(
                    id: [0xE0],
                    payload: videoPayload
                )
            )
            data.append(
                ebmlElement(
                    id: [0xAE],
                    payload: entryPayload
                )
            )
        }
        let tracksElement = ebmlElement(
            id: [0x16, 0x54, 0xAE, 0x6B],
            payload: trackEntries
        )
        let segment = ebmlElement(
            id: [0x18, 0x53, 0x80, 0x67],
            payload: tracksElement
        )
        var data = header
        data.append(segment)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("webm")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func ebmlElement(id: [UInt8], payload: Data) -> Data {
        precondition(payload.count < 127)
        var data = Data(id)
        data.append(UInt8(0x80 | payload.count))
        data.append(payload)
        return data
    }

    private struct WebMTrackFixture {
        let type: UInt8
        let codecID: String
        let alphaMode: UInt8?
    }
}

final class WebMPreparationCommandTests: XCTestCase {
    private let outputURL = URL(
        fileURLWithPath: "/tmp/reframer-prepared-output.mov"
    )

    func testAlphaSourceUsesAlphaPreservingFilterGraph() {
        let arguments = WebMPreparationSession.helperArguments(
            for: WebMProbeResult(codec: .vp9, hasAlpha: true),
            outputURL: outputURL
        )

        XCTAssertEqual(arguments.value(after: "-c:v:0"), "libvpx-vp9")
        XCTAssertNotNil(arguments.value(after: "-filter_complex"))
        XCTAssertTrue(
            arguments.value(after: "-filter_complex")?
                .contains("alphaextract") == true
        )
        XCTAssertTrue(
            arguments.value(after: "-filter_complex")?
                .contains("mergeplanes") == true
        )
        XCTAssertTrue(arguments.contains("[out]"))
        XCTAssertEqual(arguments.value(after: "-alpha_bits"), "16")
        XCTAssertEqual(arguments.value(after: "-pix_fmt"), "yuva444p10le")
        XCTAssertTrue(
            arguments.value(after: "-filter_complex")?
                .contains("[0:v:0]split") == true
        )
        XCTAssertEqual(arguments.last, outputURL.path)
    }

    func testOpaqueSourceUsesDirectVideoMapWithoutAlphaGraph() {
        let arguments = WebMPreparationSession.helperArguments(
            for: WebMProbeResult(codec: .vp8, hasAlpha: false),
            outputURL: outputURL
        )

        XCTAssertEqual(arguments.value(after: "-c:v:0"), "libvpx")
        XCTAssertNil(arguments.value(after: "-filter_complex"))
        XCTAssertFalse(arguments.contains("[out]"))
        XCTAssertNil(arguments.value(after: "-alpha_bits"))
        XCTAssertEqual(arguments.value(after: "-map"), "0:v:0")
        XCTAssertEqual(arguments.value(after: "-pix_fmt"), "yuv444p10le")
        XCTAssertEqual(arguments.last, outputURL.path)
    }

    func testSelectedVideoStreamIndexControlsDecoderAndMap() {
        let opaqueArguments = WebMPreparationSession.helperArguments(
            for: WebMProbeResult(
                codec: .vp9,
                hasAlpha: false,
                videoStreamIndex: 1
            ),
            outputURL: outputURL
        )
        XCTAssertEqual(
            opaqueArguments.value(after: "-c:v:1"),
            "libvpx-vp9"
        )
        XCTAssertEqual(opaqueArguments.value(after: "-map"), "0:v:1")

        let alphaArguments = WebMPreparationSession.helperArguments(
            for: WebMProbeResult(
                codec: .vp8,
                hasAlpha: true,
                videoStreamIndex: 2
            ),
            outputURL: outputURL
        )
        XCTAssertEqual(alphaArguments.value(after: "-c:v:2"), "libvpx")
        XCTAssertTrue(
            alphaArguments.value(after: "-filter_complex")?
                .contains("[0:v:2]split") == true
        )
    }

    func testBothBranchesKeepOptionalAudioAndSanitizeMetadata() {
        for probe in [
            WebMProbeResult(codec: .vp8, hasAlpha: false),
            WebMProbeResult(codec: .vp9, hasAlpha: true)
        ] {
            let arguments = WebMPreparationSession.helperArguments(
                for: probe,
                outputURL: outputURL
            )

            XCTAssertTrue(arguments.contains("0:a:0?"))
            XCTAssertEqual(
                arguments.value(after: "-map_metadata"),
                "-1"
            )
            XCTAssertEqual(
                arguments.value(after: "-map_chapters"),
                "-1"
            )
            XCTAssertEqual(arguments.value(after: "-c:a"), "pcm_s16le")
            XCTAssertEqual(arguments.value(after: "-profile:v"), "4")
            XCTAssertEqual(arguments.value(after: "-f"), "mov")
        }
    }
}

final class ProcessTerminationEscalationTests: XCTestCase {
    func testStopRequestTerminatesThenKillsAfterGracePeriodOnlyOnce() {
        let start = Date(timeIntervalSince1970: 100)
        var escalation = ProcessTerminationEscalation(gracePeriod: 2)

        XCTAssertEqual(
            escalation.signal(shouldStop: false, now: start),
            .none
        )
        XCTAssertEqual(
            escalation.signal(shouldStop: true, now: start),
            .terminate
        )
        XCTAssertEqual(
            escalation.signal(
                shouldStop: true,
                now: start.addingTimeInterval(1.999)
            ),
            .none
        )
        XCTAssertEqual(
            escalation.signal(
                shouldStop: true,
                now: start.addingTimeInterval(2)
            ),
            .kill
        )
        XCTAssertEqual(
            escalation.signal(
                shouldStop: true,
                now: start.addingTimeInterval(10)
            ),
            .none
        )
    }
}

final class ProcessProgressWatchdogTests: XCTestCase {
    func testProgressExtendsStallDeadlineButNotMaximumRuntime() {
        let start = Date(timeIntervalSince1970: 100)
        var watchdog = ProcessProgressWatchdog(
            startedAt: start,
            stallTimeout: 5,
            maximumRuntime: 12
        )

        XCTAssertFalse(
            watchdog.hasTimedOut(
                now: start.addingTimeInterval(4),
                outputBytes: 0
            )
        )
        XCTAssertFalse(
            watchdog.hasTimedOut(
                now: start.addingTimeInterval(4.5),
                outputBytes: 100
            )
        )
        XCTAssertFalse(
            watchdog.hasTimedOut(
                now: start.addingTimeInterval(9),
                outputBytes: 100
            )
        )
        XCTAssertTrue(
            watchdog.hasTimedOut(
                now: start.addingTimeInterval(12),
                outputBytes: 200
            ),
            "Progress must not extend the absolute runtime ceiling"
        )
    }

    func testNoOutputProgressTriggersStallTimeout() {
        let start = Date(timeIntervalSince1970: 100)
        var watchdog = ProcessProgressWatchdog(
            startedAt: start,
            stallTimeout: 5,
            maximumRuntime: 100
        )

        XCTAssertTrue(
            watchdog.hasTimedOut(
                now: start.addingTimeInterval(5),
                outputBytes: 0
            )
        )
    }
}

@MainActor
final class WebMHelperIntegrationTests: XCTestCase {
    func testBundledHelperPreservesRealVP8AndVP9AlphaPlanes() async throws {
        let fixtureNames = [
            "test_vp8_alpha_vorbis",
            "test_vp9_alpha_opus",
            "test_vp9_alpha_no_audio"
        ]
        let helperURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Reframer")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("reframer-ffmpeg")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: helperURL.path)
        )

        for fixtureName in fixtureNames {
            let fixtureURL = try XCTUnwrap(
                Bundle(for: Self.self).url(
                    forResource: fixtureName,
                    withExtension: "webm"
                )
            )
            let session = WebMPreparationSession(
                inputURL: fixtureURL,
                helperURL: helperURL,
                stallTimeout: 30,
                maximumRuntime: 60
            )
            let completion = expectation(
                description: "Prepare \(fixtureName)"
            )
            var preparationResult: Result<URL, Error>?
            session.start { result in
                preparationResult = result
                completion.fulfill()
            }
            await fulfillment(of: [completion], timeout: 30)
            defer { session.cancelAndWait() }
            let outputURL = try XCTUnwrap(preparationResult).get()
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let asset = AVURLAsset(url: outputURL)
            let assetIsPlayable = try await asset.load(.isPlayable)
            XCTAssertTrue(assetIsPlayable)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 1, accuracy: 0.1)

            let videoTracks = try await asset.loadTracks(
                withMediaType: .video
            )
            let videoTrack = try XCTUnwrap(videoTracks.first)
            let videoTrackIsPlayable = try await videoTrack.load(.isPlayable)
            let videoTrackIsDecodable = try await videoTrack.load(.isDecodable)
            XCTAssertTrue(videoTrackIsPlayable)
            XCTAssertTrue(videoTrackIsDecodable)

            let audioTracks = try await asset.loadTracks(
                withMediaType: .audio
            )
            if fixtureName == "test_vp9_alpha_no_audio" {
                XCTAssertTrue(audioTracks.isEmpty)
            } else {
                let audioTrack = try XCTUnwrap(audioTracks.first)
                let descriptions = try await audioTrack.load(
                    .formatDescriptions
                )
                XCTAssertTrue(
                    descriptions.contains {
                        CMFormatDescriptionGetMediaSubType($0)
                            == kAudioFormatLinearPCM
                    },
                    "\(fixtureName) did not produce PCM audio"
                )
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            var actualTime = CMTime.invalid
            let image = try generator.copyCGImage(
                at: CMTime(seconds: 0.5, preferredTimescale: 600),
                actualTime: &actualTime
            )
            let alphaRange = try alphaRange(in: image)

            XCTAssertLessThan(
                alphaRange.minimum,
                16,
                "\(fixtureName) lost transparent pixels"
            )
            XCTAssertGreaterThan(
                alphaRange.maximum,
                239,
                "\(fixtureName) lost opaque pixels"
            )
        }
    }

    func testFinalSparseOutputBeyondHardLimitIsRejected() async throws {
        let fixtureURL = try fixtureURL(named: "test_vp9_alpha_no_audio")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReframerOversizeHelper-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let helperURL = try createHelperScript(
            in: temporaryDirectory,
            body: """
            last=""
            for argument
            do
                last="$argument"
            done
            /usr/bin/python3 -c 'import sys; stream = open(sys.argv[1], "wb"); stream.truncate(68719476737); stream.close()' "$last"
            """
        )
        let session = WebMPreparationSession(
            inputURL: fixtureURL,
            helperURL: helperURL,
            outputDirectory: temporaryDirectory,
            stallTimeout: 30,
            maximumRuntime: 60
        )
        defer { session.cancelAndWait() }
        let completion = expectation(description: "Reject oversized output")
        var preparationResult: Result<URL, Error>?
        session.start { result in
            preparationResult = result
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 10)

        guard case .failure(let error) = preparationResult else {
            return XCTFail("Oversized sparse output unexpectedly succeeded")
        }
        XCTAssertEqual(error as? WebMPreparationError, .outputTooLarge)
    }

    func testCancellationWinsForRunningHelperProcess() async throws {
        let fixtureURL = try fixtureURL(named: "test_vp9_alpha_no_audio")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ReframerCancellationHelper-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let helperURL = try createHelperScript(
            in: temporaryDirectory,
            body: "/bin/sleep 10"
        )
        let session = WebMPreparationSession(
            inputURL: fixtureURL,
            helperURL: helperURL,
            outputDirectory: temporaryDirectory,
            stallTimeout: 30,
            maximumRuntime: 60
        )
        defer { session.cancelAndWait() }
        let completion = expectation(description: "Cancel helper")
        var preparationResult: Result<URL, Error>?
        session.start { result in
            preparationResult = result
            completion.fulfill()
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        session.cancel()

        await fulfillment(of: [completion], timeout: 5)

        guard case .failure(let error) = preparationResult else {
            return XCTFail("Cancelled preparation unexpectedly succeeded")
        }
        XCTAssertEqual(error as? WebMPreparationError, .cancelled)
    }

    private func fixtureURL(named name: String) throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: name,
                withExtension: "webm"
            )
        )
    }

    private func createHelperScript(
        in directory: URL,
        body: String
    ) throws -> URL {
        let helperURL = directory.appendingPathComponent("test-helper.sh")
        try "#!/bin/sh\n\(body)\n".write(
            to: helperURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )
        return helperURL
    }

    private func alphaRange(
        in image: CGImage
    ) throws -> (minimum: UInt8, maximum: UInt8) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.sRGB)
        )
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let address = buffer.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        XCTAssertTrue(rendered)
        guard rendered else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let alphaValues = stride(from: 3, to: pixels.count, by: 4)
            .map { pixels[$0] }
        return (
            try XCTUnwrap(alphaValues.min()),
            try XCTUnwrap(alphaValues.max())
        )
    }
}

@MainActor
final class MediaCapabilityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "Reframer.MediaCapabilityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testYouTubeDisablesTransformsFiltersAndExactFrameNavigation() throws {
        let state = VideoState(defaults: defaults)
        state.showFilterPanel = true
        state.isLocked = true
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/dQw4w9WgXcQ"
            )
        )

        state.loadYouTube(
            YouTubePlaybackAuthorization(
                reference: reference,
                audience: .general
            )
        )

        XCTAssertFalse(state.supportsVideoTransforms)
        XCTAssertFalse(state.supportsVideoFilters)
        XCTAssertFalse(state.supportsClickThroughLock)
        XCTAssertFalse(state.canNavigateFrames)
        XCTAssertFalse(state.showFilterPanel)
        XCTAssertFalse(state.isLocked)
        XCTAssertEqual(state.currentSourceDisplayName, "YouTube video")
    }

    func testPendingYouTubeSelectionDisablesNativeOnlyToolsImmediately() {
        let state = VideoState(defaults: defaults)
        state.showFilterPanel = true
        state.isLocked = true

        _ = state.beginPendingMediaSelection(displayName: "YouTube video")

        XCTAssertFalse(state.supportsVideoTransforms)
        XCTAssertFalse(state.supportsVideoFilters)
        XCTAssertFalse(state.supportsClickThroughLock)
        XCTAssertFalse(state.showFilterPanel)
        XCTAssertFalse(state.isLocked)
        XCTAssertEqual(state.currentSourceDisplayName, "YouTube video")
    }

    func testPendingYouTubeLoadingStateSurvivesNativeViewCleanup() async {
        let state = VideoState(defaults: defaults)
        let nativeView = VideoView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 360)
        )
        nativeView.videoState = state

        _ = state.beginPendingMediaSelection(displayName: "YouTube video")
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(state.isVideoLoading)
        XCTAssertFalse(state.isVideoLoaded)
        XCTAssertNil(state.videoErrorMessage)
        withExtendedLifetime(nativeView) {}
    }

    func testEmbeddedPlayerAudioReconcilesMuteAndRestoresItsVolume() {
        let state = VideoState(defaults: defaults)
        state.volume = 0.4
        state.isMuted = false

        state.reconcileExternalAudio(volume: 0.7, isMuted: true)
        XCTAssertTrue(state.isMuted)
        XCTAssertEqual(state.volume, 0)
        XCTAssertEqual(
            state.playerVolumeWhenUnmuted,
            0.7,
            accuracy: 0.0001
        )

        state.reconcileExternalAudio(volume: 0.7, isMuted: false)
        XCTAssertFalse(state.isMuted)
        XCTAssertEqual(state.volume, 0.7, accuracy: 0.0001)
    }

    func testLocalWebMRetainsNativeTransformAndFilterCapabilities() {
        let state = VideoState(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/transparent.webm")

        state.loadLocalMedia(url)

        XCTAssertEqual(state.webMediaSource, .localWebM(url))
        XCTAssertTrue(state.supportsVideoTransforms)
        XCTAssertTrue(state.supportsVideoFilters)
        XCTAssertFalse(state.supportsClickThroughLock)
        state.isVideoLoaded = true
        XCTAssertTrue(state.supportsClickThroughLock)
        XCTAssertEqual(
            state.currentSourceDisplayName,
            "transparent.webm"
        )
    }

    func testYouTubeCommandContextRetainsTransportButBlocksNativeOnlyTools() {
        let context = ReframerCommandAvailabilityContext(
            isVideoLoaded: true,
            isLocked: false,
            canNavigateFrames: false,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false,
            canTransformMedia: false,
            canUseVideoFilters: false,
            canUseClickThroughLock: false
        )

        XCTAssertTrue(
            ReframerCommandAvailability.isAvailable(
                .togglePlayPause,
                origin: .localShortcut,
                context: context
            )
        )
        XCTAssertFalse(
            ReframerCommandAvailability.isAvailable(
                .step(.forward, amount: 1),
                origin: .localShortcut,
                context: context
            )
        )
        for command in [
            ReframerCommand.pan(x: 1, y: 0),
            .resetZoom,
            .resetView,
            .toggleFilterPanel,
            .toggleLock
        ] {
            XCTAssertFalse(
                ReframerCommandAvailability.isAvailable(
                    command,
                    origin: .localShortcut,
                    context: context
                )
            )
        }
    }

    func testLockCommandRequiresLoadedLocalMediaButAlwaysAllowsRecovery() {
        let empty = ReframerCommandAvailabilityContext(
            isVideoLoaded: false,
            isLocked: false,
            canNavigateFrames: false,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false,
            canUseClickThroughLock: true
        )
        XCTAssertFalse(
            ReframerCommandAvailability.isAvailable(
                .toggleLock,
                origin: .localShortcut,
                context: empty
            )
        )

        let pending = ReframerCommandAvailabilityContext(
            isVideoLoaded: false,
            isLocked: false,
            canNavigateFrames: false,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false,
            canUseClickThroughLock: false
        )
        XCTAssertFalse(
            ReframerCommandAvailability.isAvailable(
                .toggleLock,
                origin: .globalShortcut,
                context: pending
            )
        )

        let loadedLocal = ReframerCommandAvailabilityContext(
            isVideoLoaded: true,
            isLocked: false,
            canNavigateFrames: true,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false,
            canUseClickThroughLock: true
        )
        XCTAssertTrue(
            ReframerCommandAvailability.isAvailable(
                .toggleLock,
                origin: .globalShortcut,
                context: loadedLocal
            )
        )

        let lockedRecovery = ReframerCommandAvailabilityContext(
            isVideoLoaded: false,
            isLocked: true,
            canNavigateFrames: false,
            isHelpVisible: false,
            isFilterPanelVisible: false,
            isDocumentationVisible: false,
            canUseClickThroughLock: false
        )
        XCTAssertTrue(
            ReframerCommandAvailability.isAvailable(
                .toggleLock,
                origin: .globalShortcut,
                context: lockedRecovery
            )
        )
    }

    func testYouTubeReloadRoutesBackThroughCompliancePreflight() throws {
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/dQw4w9WgXcQ"
            )
        )
        let source = WebMediaSource.youtube(
            YouTubePlaybackAuthorization(
                reference: reference,
                audience: .general
            )
        )

        XCTAssertEqual(
            YouTubeReloadPolicy.reference(for: source),
            reference
        )
        XCTAssertNil(
            YouTubeReloadPolicy.reference(
                for: .localWebM(
                    URL(fileURLWithPath: "/tmp/transparent.webm")
                )
            )
        )
        XCTAssertNil(YouTubeReloadPolicy.reference(for: nil))
    }

    func testLateYouTubeAuthorizationCannotReplaceNewerLocalSelection()
        throws {
        let state = VideoState(defaults: defaults)
        let pendingRevision = state.beginPendingMediaSelection()
        let localURL = URL(fileURLWithPath: "/tmp/newer-selection.mov")
        state.loadLocalMedia(localURL)
        let reference = try XCTUnwrap(
            YouTubeVideoReference.parse(
                "https://youtu.be/dQw4w9WgXcQ"
            )
        )

        XCTAssertFalse(
            state.loadYouTube(
                YouTubePlaybackAuthorization(
                    reference: reference,
                    audience: .general
                ),
                ifCurrent: pendingRevision
            )
        )
        XCTAssertEqual(state.videoURL, localURL)
        XCTAssertNil(state.webMediaSource)
    }
}

private final class URLRequestRecorder {
    private let lock = NSLock()
    private var request: URLRequest?

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func record(_ request: URLRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }
}

private final class LockedRequestCount {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class YouTubeMockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handler: Handler?

    static func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    static func removeHandler() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }
}

private extension Array where Element == String {
    func value(after flag: String) -> String? {
        guard let index = firstIndex(of: flag),
              index < self.index(before: endIndex) else {
            return nil
        }
        return self[self.index(after: index)]
    }
}
