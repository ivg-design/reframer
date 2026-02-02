import Foundation

enum UITestConfig {
    static func value(for key: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let envPath = home.appendingPathComponent("ci_artifacts/reframer/launchd/runner.env")
        guard let contents = try? String(contentsOf: envPath) else {
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
