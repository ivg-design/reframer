import XCTest

enum UITestConfig {
    private static let isolatedPreferencesSuite = "com.reframer.app.uitests"

    /// Gives every UI launch deterministic defaults without deleting or
    /// overwriting the user's real Reframer preferences.
    static func configure(
        _ app: XCUIApplication,
        resetPreferences: Bool = true
    ) {
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["UITEST_PREFERENCES_SUITE"] = isolatedPreferencesSuite
        app.launchEnvironment["UITEST_RESET_PREFERENCES"] =
            resetPreferences ? "1" : "0"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    }

    static func value(for key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let envPath = home.appendingPathComponent("ci_artifacts/reframer/launchd/runner.env")
        guard let contents = try? String(contentsOf: envPath, encoding: .utf8) else {
            return nil
        }

        for rawLine in contents.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if name == key && !value.isEmpty {
                return value
            }
        }

        return nil
    }
}
