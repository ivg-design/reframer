import XCTest
@testable import Reframer

final class YouTubeResolverTests: XCTestCase {
    func testSelectionPrefersHighestQualityStreams() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/youtube-sample.json")

        let data = try Data(contentsOf: fixtureURL)
        let selection = try YouTubeResolver.shared.selectionFromJSONData(data)

        XCTAssertEqual(selection.title, "Sample Video")
        XCTAssertEqual(selection.primary.videoURL.absoluteString, "https://example.com/combined4k.webm")
        XCTAssertNil(selection.primary.audioURL)
        XCTAssertFalse(selection.primary.isAVFoundationCompatible)
    }
}
