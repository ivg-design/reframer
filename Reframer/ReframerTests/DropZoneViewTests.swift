import XCTest
@testable import Reframer

@MainActor
final class DropZoneViewTests: XCTestCase {
    func testLoadVideoAcceptsSupportedExtension() {
        let state = VideoState()
        let view = DropZoneView(frame: .zero)
        view.videoState = state

        let url = URL(fileURLWithPath: "/tmp/sample.mp4")
        let success = view.loadVideo(from: url)

        XCTAssertTrue(success)
        XCTAssertEqual(state.videoURL, url)
        XCTAssertFalse(state.isVideoLoaded, "Load should defer until player is ready")
    }

    func testLoadVideoRejectsUnsupportedExtension() {
        let state = VideoState()
        let view = DropZoneView(frame: .zero)
        view.videoState = state

        let url = URL(fileURLWithPath: "/tmp/sample.png")
        let success = view.loadVideo(from: url)

        XCTAssertFalse(success)
        XCTAssertNil(state.videoURL)
    }
}
