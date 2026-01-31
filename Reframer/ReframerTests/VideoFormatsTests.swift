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

    func testAVISupported() {
        XCTAssertTrue(VideoFormats.supportedExtensions.contains("avi"),
                      "AVI should be a supported format")
    }

    func testMKVSupported() {
        XCTAssertTrue(VideoFormats.supportedExtensions.contains("mkv"),
                      "MKV should be a supported format")
    }

    func testWebMSupported() {
        XCTAssertTrue(VideoFormats.supportedExtensions.contains("webm"),
                      "WebM should be a supported format")
    }

    func testSupportedTypesNotEmpty() {
        XCTAssertFalse(VideoFormats.supportedTypes.isEmpty, "There should be supported types")
        XCTAssertGreaterThan(VideoFormats.supportedTypes.count, 5, "Should support multiple types")
    }

    func testSupportedExtensionsNotEmpty() {
        XCTAssertFalse(VideoFormats.supportedExtensions.isEmpty, "Should have supported extensions")
        XCTAssertGreaterThan(VideoFormats.supportedExtensions.count, 10, "Should support many extensions")
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

    // MARK: - UTType support

    func testMPEG4MovieTypeSupported() {
        XCTAssertTrue(VideoFormats.supportedTypes.contains(.mpeg4Movie),
                      "MPEG4 movie type should be supported")
    }

    func testQuickTimeMovieTypeSupported() {
        XCTAssertTrue(VideoFormats.supportedTypes.contains(.quickTimeMovie),
                      "QuickTime movie type should be supported")
    }

    func testAVITypeSupported() {
        XCTAssertTrue(VideoFormats.supportedTypes.contains(.avi),
                      "AVI type should be supported")
    }

    // MARK: - Display String

    func testDisplayStringNotEmpty() {
        XCTAssertFalse(VideoFormats.displayString.isEmpty, "Display string should not be empty")
        XCTAssertTrue(VideoFormats.displayString.contains("MP4"), "Display string should mention MP4")
    }
}
