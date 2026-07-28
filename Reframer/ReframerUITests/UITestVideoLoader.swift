import AppKit
import XCTest

enum UITestVideoLoader {
    static func fixtureURL(
        named name: String,
        extension fileExtension: String = "mp4",
        relativeTo testSourceFile: StaticString = #filePath
    ) -> URL {
        URL(fileURLWithPath: "\(testSourceFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ReframerTests/TestFixtures", isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension(fileExtension)
    }

    /// Opens a fixture through Launch Services so the sandbox receives the
    /// same user-selected read-only extension as Finder's Open With flow.
    static func open(
        _ videoURL: URL,
        in app: XCUIApplication,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            XCTFail("Missing UI-test fixture: \(videoURL.path)", file: file, line: line)
            return false
        }
        guard app.wait(for: .runningForeground, timeout: timeout) else {
            XCTFail("Reframer did not reach the foreground", file: file, line: line)
            return false
        }

        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.reframer.app" && !$0.isTerminated
        }
        guard let runningApplication = candidates.max(by: {
            $0.processIdentifier < $1.processIdentifier
        }), let applicationURL = runningApplication.bundleURL else {
            XCTFail("Could not locate the launched Reframer bundle", file: file, line: line)
            return false
        }

        let opened = XCTestExpectation(description: "Open fixture through Launch Services")
        var openError: Error?
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(
            [videoURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            openError = error
            opened.fulfill()
        }

        guard XCTWaiter.wait(for: [opened], timeout: timeout) == .completed else {
            XCTFail("Launch Services did not finish opening the fixture", file: file, line: line)
            return false
        }
        if let openError {
            XCTFail("Launch Services could not open the fixture: \(openError)", file: file, line: line)
            return false
        }
        return true
    }
}
