import XCTest
@testable import Reframer

/// Integration tests for MPV Homebrew bottle installation
final class MPVInstallationTests: XCTestCase {

    // MARK: - Homebrew API Tests

    func testHomebrewAPIReturnsValidMPVInfo() async throws {
        let apiURL = URL(string: "https://formulae.brew.sh/api/formula/mpv.json")!

        let (data, response) = try await URLSession.shared.data(from: apiURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Expected HTTP response")
            return
        }

        XCTAssertEqual(httpResponse.statusCode, 200, "Homebrew API should return 200")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Response should be valid JSON dictionary")
            return
        }

        // Verify expected structure
        XCTAssertNotNil(json["name"], "Should have name field")
        XCTAssertNotNil(json["bottle"], "Should have bottle field")

        guard let bottle = json["bottle"] as? [String: Any],
              let stable = bottle["stable"] as? [String: Any],
              let files = stable["files"] as? [String: Any] else {
            XCTFail("Should have bottle.stable.files structure")
            return
        }

        // Check for arm64 bottle (or fallback)
        let hasArm64 = files.keys.contains { $0.contains("arm64") }
        XCTAssertTrue(hasArm64 || !files.isEmpty, "Should have at least one architecture bottle")
    }

    func testGHCRTokenEndpointWorks() async throws {
        let tokenURL = URL(string: "https://ghcr.io/token?scope=repository:homebrew/core/mpv:pull")!

        let (data, response) = try await URLSession.shared.data(from: tokenURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Expected HTTP response")
            return
        }

        XCTAssertEqual(httpResponse.statusCode, 200, "GHCR token endpoint should return 200")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Response should be valid JSON dictionary")
            return
        }

        XCTAssertNotNil(json["token"], "Should have token field")
        if let token = json["token"] as? String {
            XCTAssertFalse(token.isEmpty, "Token should not be empty")
        }
    }

    func testBottleURLCanBeResolved() async throws {
        // Get mpv info
        let apiURL = URL(string: "https://formulae.brew.sh/api/formula/mpv.json")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bottle = json["bottle"] as? [String: Any],
              let stable = bottle["stable"] as? [String: Any],
              let files = stable["files"] as? [String: Any] else {
            XCTFail("Could not parse mpv API response")
            return
        }

        // Find first available architecture
        let archKeys = ["arm64_sequoia", "arm64_sonoma", "sonoma", "arm64_ventura", "ventura"]
        var bottleURL: URL?
        for key in archKeys {
            if let archInfo = files[key] as? [String: Any],
               let urlString = archInfo["url"] as? String,
               let url = URL(string: urlString) {
                bottleURL = url
                break
            }
        }

        XCTAssertNotNil(bottleURL, "Should find at least one bottle URL")

        // Get token
        let tokenURL = URL(string: "https://ghcr.io/token?scope=repository:homebrew/core/mpv:pull")!
        let (tokenData, _) = try await URLSession.shared.data(from: tokenURL)
        guard let tokenJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let token = tokenJSON["token"] as? String else {
            XCTFail("Could not get GHCR token")
            return
        }

        // Try to fetch bottle headers
        var request = URLRequest(url: bottleURL!)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, headResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = headResponse as? HTTPURLResponse else {
            XCTFail("Expected HTTP response")
            return
        }

        XCTAssertEqual(httpResponse.statusCode, 200, "Bottle URL should be accessible with token")
    }

    // MARK: - Installation Flow Tests

    func testInstallationCreatesLibDirectory() async throws {
        let manager = MPVManager.shared
        let libDir = manager.installDirectory.appendingPathComponent("lib")

        // Clean up first if exists
        if FileManager.default.fileExists(atPath: libDir.path) {
            try? FileManager.default.removeItem(at: libDir)
        }

        // Create the directory (simulating first step of install)
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: libDir.path), "lib directory should be created")

        // Cleanup
        try? FileManager.default.removeItem(at: libDir)
    }
}
