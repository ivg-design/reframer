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
        // A preceding cross-application hot-key test may leave Finder active
        // for a moment after launch. Explicit activation makes the fixture
        // handoff deterministic without changing application behavior.
        if !app.wait(for: .runningForeground, timeout: min(2, timeout)) {
            app.activate()
        }
        guard app.wait(for: .runningForeground, timeout: timeout) else {
            XCTFail("Reframer did not reach the foreground", file: file, line: line)
            return false
        }

        guard let runningApplication = NSWorkspace.shared.frontmostApplication,
              runningApplication.bundleIdentifier == "com.reframer.app",
              !runningApplication.isTerminated,
              let applicationURL = runningApplication.bundleURL else {
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

    static func openAndWaitForReady(
        _ videoURL: URL,
        in app: XCUIApplication,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard open(videoURL, in: app, timeout: timeout, file: file, line: line) else {
            return false
        }

        let timeline = app.sliders["slider-timeline"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isEnabled == true"),
            object: timeline
        )
        guard XCTWaiter.wait(for: [ready], timeout: timeout) == .completed else {
            XCTFail(
                "The Launch Services fixture did not reach ready playback state",
                file: file,
                line: line
            )
            return false
        }
        return true
    }
}
