import XCTest
@testable import Reframer

final class YouTubeResolverTests: XCTestCase {
    func testSelectionPrefersAVFoundationVideoAndAudio() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/youtube-sample.json")

        let data = try Data(contentsOf: fixtureURL)
        let selection = try YouTubeResolver.shared.selectionFromJSONData(data)

        XCTAssertEqual(selection.title, "Sample Video")
        XCTAssertEqual(selection.primary.videoURL.absoluteString, "https://example.com/video1080.mp4")
        XCTAssertEqual(selection.primary.audioURL?.absoluteString, "https://example.com/audio.m4a")
        XCTAssertTrue(selection.primary.isAVFoundationCompatible)
    }
}
