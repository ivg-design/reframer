import AVFoundation
import XCTest
@testable import Reframer

enum TestError: Error {
    case fixtureNotFound(String)
    case noVideoTrack
    case loadFailed(String)
}

/// Helper class for loading test video fixtures
class VideoTestHelper {

    /// Load a test video fixture from the test bundle
    /// - Parameter name: The fixture name without extension
    /// - Returns: Tuple containing the player, duration in seconds, and fps
    static func loadFixture(_ name: String) async throws -> (AVPlayer, duration: Double, fps: Double) {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "mp4") else {
            throw TestError.fixtureNotFound(name)
        }

        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TestError.noVideoTrack
        }

        let fps = try await Double(track.load(.nominalFrameRate))
        let player = AVPlayer(url: url)

        return (player, duration, fps)
    }

    /// Wait for a player to be ready to play
    static func waitForPlayerReady(_ player: AVPlayer, timeout: TimeInterval = 5.0) async throws {
        let startTime = Date()
        while player.currentItem?.status != .readyToPlay {
            if Date().timeIntervalSince(startTime) > timeout {
                throw TestError.loadFailed("Player did not become ready within \(timeout) seconds")
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
}

/// Extension to provide test-specific VideoState initialization
extension XCTestCase {

    /// Creates a fresh VideoState for testing
    @MainActor
    func createTestVideoState() -> VideoState {
        return VideoState()
    }
}
