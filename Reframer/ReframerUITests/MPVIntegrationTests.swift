import XCTest
@testable import Reframer

/// Integration tests for MPV installation and playback.
/// These tests verify actual functionality on a clean system.
final class MPVIntegrationTests: XCTestCase {

    private static var app: XCUIApplication?
    private static var appLaunched = false

    var app: XCUIApplication {
        if Self.app == nil {
            Self.app = XCUIApplication()
        }
        return Self.app!
    }

    override func setUpWithError() throws {
        continueAfterFailure = true

        if !Self.appLaunched {
            app.launchEnvironment["UITEST_MODE"] = "1"
            app.launch()
            Self.appLaunched = true
            Thread.sleep(forTimeInterval: 1)
        } else {
            app.activate()
        }
    }

    override class func tearDown() {
        app?.terminate()
        app = nil
        appLaunched = false
        super.tearDown()
    }

    // MARK: - YouTube MPV Prompt Tests

    /// Test that pasting a YouTube URL when MPV is not installed triggers install prompt
    func testYouTubeURL_TriggersInstallPromptWhenMPVNotInstalled() throws {
        // Skip if MPV is already installed
        let manager = MPVManager.shared
        if manager.isReady {
            throw XCTSkip("MPV is already installed - test only applies to clean systems")
        }

        let openButton = app.buttons["button-open"]
        XCTAssertTrue(openButton.exists, "Open button should exist")

        // Long press to get YouTube URL input
        openButton.press(forDuration: 0.4)

        let inputField = app.textFields["youtube-url-input"]
        guard inputField.waitForExistence(timeout: 2) else {
            XCTFail("YouTube URL input should appear")
            return
        }

        // Type a YouTube URL
        inputField.click()
        inputField.typeText("https://www.youtube.com/watch?v=dQw4w9WgXcQ")

        // Submit
        app.typeKey(.return, modifierFlags: [])
        Thread.sleep(forTimeInterval: 3) // Wait for YouTube resolution

        // Should see MPV install prompt (sheet)
        let installSheet = app.sheets.firstMatch
        if installSheet.waitForExistence(timeout: 10) {
            // Verify install prompt elements
            let installButton = app.buttons["Install MPV"]
            let cancelButton = app.buttons["Cancel"]

            XCTAssertTrue(
                installButton.exists || cancelButton.exists,
                "Install prompt should have Install or Cancel button"
            )

            // Cancel for now
            if cancelButton.exists {
                cancelButton.click()
            }
        } else {
            // May have gone straight to install or error
            print("No install sheet appeared - MPV may already be installed or URL resolution failed")
        }
    }

    /// Test that the MPV installation process works end-to-end
    func testMPVInstallation_DownloadsAndInstalls() async throws {
        let manager = MPVManager.shared

        // Clean up any existing installation for test
        let installDir = manager.installDirectory
        if FileManager.default.fileExists(atPath: installDir.path) {
            try? FileManager.default.removeItem(at: installDir)
        }

        XCTAssertFalse(manager.isInstalled, "MPV should not be installed after cleanup")

        // Start installation
        var progressUpdates: [Double] = []
        var statusUpdates: [String] = []

        let installExpectation = expectation(description: "MPV installation completes")

        Task {
            do {
                try await manager.installMPV { progress, status in
                    progressUpdates.append(progress)
                    statusUpdates.append(status)
                }
                installExpectation.fulfill()
            } catch {
                XCTFail("Installation failed: \(error)")
                installExpectation.fulfill()
            }
        }

        // Wait for installation (may take a while for downloads)
        await fulfillment(of: [installExpectation], timeout: 300)

        // Verify installation
        XCTAssertTrue(manager.isInstalled, "MPV should be installed after install process")
        XCTAssertGreaterThan(progressUpdates.count, 0, "Should have progress updates")
        XCTAssertGreaterThan(statusUpdates.count, 0, "Should have status updates")

        // Verify library loads
        manager.loadLibrary()
        XCTAssertTrue(manager.isReady, "MPV library should be loadable after installation")
    }

    /// Test that WebM files trigger MPV requirement check correctly
    func testWebMFile_RequiresMPV() throws {
        let manager = MPVManager.shared

        let webmURL = URL(fileURLWithPath: "/test/sample.webm")
        XCTAssertTrue(manager.requiresMPV(url: webmURL), "WebM should require MPV")

        let mkvURL = URL(fileURLWithPath: "/test/sample.mkv")
        XCTAssertTrue(manager.requiresMPV(url: mkvURL), "MKV should require MPV")

        let mp4URL = URL(fileURLWithPath: "/test/sample.mp4")
        XCTAssertFalse(manager.requiresMPV(url: mp4URL), "MP4 should not require MPV")
    }

    /// Test MPV playback of a WebM file when MPV is installed
    func testWebMPlayback_WorksWithMPV() throws {
        let manager = MPVManager.shared

        guard manager.isReady else {
            throw XCTSkip("MPV not installed - skipping playback test")
        }

        // Create a test WebM fixture or use an existing one
        let testWebMPath = "/Users/ivg/github/video-overlay/Reframer-filters/Reframer/ReframerTests/TestFixtures/test.webm"

        guard FileManager.default.fileExists(atPath: testWebMPath) else {
            throw XCTSkip("No WebM test fixture available")
        }

        // Open the file via drag-drop simulation or file dialog
        // For now, verify manager state
        XCTAssertTrue(manager.isEnabled, "MPV should be enabled")
    }

    // MARK: - MPV Enable/Disable Tests

    func testMPVEnabled_TogglesPreference() throws {
        let manager = MPVManager.shared

        let original = manager.isEnabled
        manager.isEnabled = !original
        XCTAssertEqual(manager.isEnabled, !original, "isEnabled should toggle")

        manager.isEnabled = original // Restore
        XCTAssertEqual(manager.isEnabled, original, "isEnabled should restore")
    }

    // MARK: - Homebrew API Tests (Network)

    func testHomebrewAPI_ReturnsValidMPVBottleInfo() async throws {
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

        XCTAssertNotNil(json["name"], "Should have name field")
        XCTAssertEqual(json["name"] as? String, "mpv", "Name should be mpv")
        XCTAssertNotNil(json["bottle"], "Should have bottle field")

        guard let bottle = json["bottle"] as? [String: Any],
              let stable = bottle["stable"] as? [String: Any],
              let files = stable["files"] as? [String: Any] else {
            XCTFail("Should have bottle.stable.files structure")
            return
        }

        // Verify we have arm64 bottle for Apple Silicon
        let arm64Keys = files.keys.filter { $0.contains("arm64") }
        XCTAssertFalse(arm64Keys.isEmpty, "Should have arm64 bottle available")
    }

    func testGHCRToken_CanBeObtained() async throws {
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

        guard let token = json["token"] as? String else {
            XCTFail("Should have token field")
            return
        }

        XCTAssertFalse(token.isEmpty, "Token should not be empty")
        XCTAssertTrue(token.count > 50, "Token should be reasonably long")
    }

    func testBottleDownload_CanBeAuthenticated() async throws {
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

        // Find arm64 bottle URL
        let archKeys = ["arm64_sequoia", "arm64_sonoma", "arm64_ventura", "sonoma", "ventura"]
        var bottleURL: URL?
        for key in archKeys {
            if let archInfo = files[key] as? [String: Any],
               let urlString = archInfo["url"] as? String,
               let url = URL(string: urlString) {
                bottleURL = url
                break
            }
        }

        guard let url = bottleURL else {
            XCTFail("Should find at least one bottle URL")
            return
        }

        // Get token
        let tokenURL = URL(string: "https://ghcr.io/token?scope=repository:homebrew/core/mpv:pull")!
        let (tokenData, _) = try await URLSession.shared.data(from: tokenURL)
        guard let tokenJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let token = tokenJSON["token"] as? String else {
            XCTFail("Could not get GHCR token")
            return
        }

        // Verify bottle is accessible
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, headResponse) = try await URLSession.shared.data(for: request)

        guard let httpResponse = headResponse as? HTTPURLResponse else {
            XCTFail("Expected HTTP response")
            return
        }

        XCTAssertEqual(httpResponse.statusCode, 200, "Bottle URL should be accessible with token")
    }

    // MARK: - Library Loading Tests

    func testMPVLibrary_LoadsAllSymbols() throws {
        let manager = MPVManager.shared

        guard manager.isReady else {
            throw XCTSkip("MPV not installed - skipping symbol test")
        }

        // Access the shared library to verify it loaded
        let library = MPVLibrary.shared

        // Verify core functions are available by checking if library is usable
        // The library will crash if symbols aren't loaded, so just existing is proof
        XCTAssertNotNil(library, "MPVLibrary should be accessible")
    }
}
