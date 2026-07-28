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
}
