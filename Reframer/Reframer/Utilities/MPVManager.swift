import Foundation
import os.log
import Darwin

/// Manages libmpv installation and loading for extended format support
final class MPVManager {
    static let shared = MPVManager()

    private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.reframer", category: "MPVManager")

    // Homebrew bottle API
    private let homebrewAPIBase = "https://formulae.brew.sh/api/formula/"
    private let ghcrTokenURL = "https://ghcr.io/token?scope=repository:homebrew/core/%@:pull"

    // Core packages needed for libmpv (order matters for linking)
    private let requiredPackages = [
        "mpv",
        "ffmpeg",
        "libass",
        "libplacebo",
        "little-cms2",
        "luajit",
        "mujs",
        "libarchive",
        "libbluray",
        "rubberband",
        "uchardet",
        "zimg"
    ]

    private var mpvDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Reframer/MPV", isDirectory: true)
    }

    private var libDirectory: URL {
        mpvDirectory.appendingPathComponent("lib", isDirectory: true)
    }

    var installDirectory: URL {
        mpvDirectory
    }

    private var cachedLibPath: URL?

    /// Check if libmpv is installed
    var isInstalled: Bool {
        libMPVPath != nil
    }

    /// Check if libmpv is enabled in preferences
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "MPVEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "MPVEnabled") }
    }

    /// Check if libmpv is loaded
    var isLoaded: Bool {
        MPVLibrary.shared.isLoaded
    }

    /// Check if libmpv is ready to use (installed + enabled + loaded)
    var isReady: Bool {
        isInstalled && isEnabled && isLoaded
    }

    /// Try to load libmpv if already installed and enabled
    func loadLibrary() {
        guard isEnabled else { return }
        guard let libPath = libMPVPath else { return }
        if MPVLibrary.shared.isLoaded { return }
        configureEnvironment(for: libPath)
        do {
            try MPVLibrary.shared.load(at: libPath.path)
            os_log("MPV: Loaded libmpv at %{public}@", log: log, type: .info, libPath.path)
        } catch {
            os_log("MPV: Failed to load libmpv - %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }

    /// Download and install libmpv from Homebrew bottles
    func install(progressHandler: @escaping (Double, String) -> Void,
                 completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            if FileManager.default.fileExists(atPath: libDirectory.path) {
                try FileManager.default.removeItem(at: libDirectory)
            }
            try FileManager.default.createDirectory(at: libDirectory, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        os_log("MPV: Starting Homebrew bottle installation", log: log, type: .info)
        progressHandler(0.0, "Fetching package info...")

        // Download packages sequentially
        downloadPackages(packages: requiredPackages, index: 0, progressHandler: progressHandler) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                // Fix library paths
                DispatchQueue.main.async {
                    progressHandler(0.9, "Configuring libraries...")
                }
                self.fixLibraryPaths { fixResult in
                    switch fixResult {
                    case .success:
                        DispatchQueue.main.async {
                            progressHandler(0.95, "Verifying installation...")
                        }
                        self.verifyInstallation { verifyResult in
                            switch verifyResult {
                            case .success:
                                DispatchQueue.main.async {
                                    progressHandler(1.0, "Installation complete")
                                    self.cachedLibPath = nil // Reset cache
                                    completion(.success(()))
                                }
                            case .failure(let error):
                                self.cleanupFailedInstall()
                                DispatchQueue.main.async { completion(.failure(error)) }
                            }
                        }
                    case .failure(let error):
                        self.cleanupFailedInstall()
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                }
            case .failure(let error):
                self.cleanupFailedInstall()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func downloadPackages(packages: [String], index: Int,
                                   progressHandler: @escaping (Double, String) -> Void,
                                   completion: @escaping (Result<Void, Error>) -> Void) {
        guard index < packages.count else {
            completion(.success(()))
            return
        }

        let package = packages[index]
        let progress = Double(index) / Double(packages.count) * 0.8
        DispatchQueue.main.async {
            progressHandler(progress, "Downloading \(package)...")
        }

        downloadPackage(name: package) { [weak self] result in
            switch result {
            case .success:
                self?.downloadPackages(packages: packages, index: index + 1,
                                       progressHandler: progressHandler, completion: completion)
            case .failure(let error):
                os_log("MPV: Failed to download %{public}@: %{public}@", log: self?.log ?? .default, type: .error,
                       package, error.localizedDescription)
                completion(.failure(error))
            }
        }
    }

    private func downloadPackage(name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get package info from Homebrew API
        let apiURL = URL(string: "\(homebrewAPIBase)\(name).json")!

        URLSession.shared.dataTask(with: apiURL) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion(.failure(MPVError.downloadFailed))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let bottle = json["bottle"] as? [String: Any],
                  let stable = bottle["stable"] as? [String: Any],
                  let files = stable["files"] as? [String: Any] else {
                completion(.failure(MPVError.downloadFailed))
                return
            }

            // Select bottle for current architecture
            let archKey = self.currentArchKey()
            guard let archInfo = files[archKey] as? [String: Any],
                  let urlString = archInfo["url"] as? String,
                  let bottleURL = URL(string: urlString) else {
                // Try fallback architectures
                let fallbacks = ["arm64_sequoia", "arm64_sonoma", "sonoma", "arm64_ventura", "ventura"]
                for fallback in fallbacks {
                    if let info = files[fallback] as? [String: Any],
                       let urlStr = info["url"] as? String,
                       let url = URL(string: urlStr) {
                        self.downloadBottle(name: name, url: url, completion: completion)
                        return
                    }
                }
                completion(.failure(MPVError.downloadFailed))
                return
            }

            self.downloadBottle(name: name, url: bottleURL, completion: completion)
        }.resume()
    }

    private func downloadBottle(name: String, url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        // Get token for ghcr.io
        let tokenURLString = String(format: ghcrTokenURL, name)
        guard let tokenURL = URL(string: tokenURLString) else {
            completion(.failure(MPVError.downloadFailed))
            return
        }

        URLSession.shared.dataTask(with: tokenURL) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String else {
                completion(.failure(MPVError.downloadFailed))
                return
            }

            // Download bottle with auth
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    completion(.failure(MPVError.downloadFailed))
                    return
                }

                guard let tempURL = tempURL else {
                    completion(.failure(MPVError.downloadFailed))
                    return
                }

                // Extract bottle
                self.extractBottle(name: name, tempURL: tempURL, completion: completion)
            }.resume()
        }.resume()
    }

    private func extractBottle(name: String, tempURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("brew-\(name)-\(UUID().uuidString)")

            do {
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                // Extract tar.gz
                let tarProcess = Process()
                tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tarProcess.arguments = ["-xf", tempURL.path, "-C", extractDir.path]
                try tarProcess.run()
                tarProcess.waitUntilExit()

                guard tarProcess.terminationStatus == 0 else {
                    throw MPVError.extractFailed
                }

                // Find and copy dylibs
                self.copyDylibs(from: extractDir, to: self.libDirectory)

                // Cleanup
                try? FileManager.default.removeItem(at: extractDir)

                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func copyDylibs(from source: URL, to destination: URL) {
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if filename.hasSuffix(".dylib") {
                let destPath = destination.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: destPath)
                try? FileManager.default.copyItem(at: fileURL, to: destPath)
            }
        }
    }

    private func fixLibraryPaths(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let systemPrefixes = ["/usr/lib/", "/System/Library/"]

            guard let enumerator = FileManager.default.enumerator(at: self.libDirectory, includingPropertiesForKeys: nil) else {
                completion(.success(()))
                return
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "dylib" else { continue }

                // Get current dependencies
                let otoolProcess = Process()
                otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
                otoolProcess.arguments = ["-L", fileURL.path]
                let pipe = Pipe()
                otoolProcess.standardOutput = pipe
                try? otoolProcess.run()
                otoolProcess.waitUntilExit()

                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                // Fix paths containing @@HOMEBREW_PREFIX@@ or absolute Homebrew paths
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard let oldPath = trimmed.components(separatedBy: " ").first, !oldPath.isEmpty else {
                        continue
                    }

                    if systemPrefixes.contains(where: { oldPath.hasPrefix($0) }) {
                        continue
                    }

                    let libName = (oldPath as NSString).lastPathComponent
                    let localCandidate = self.libDirectory.appendingPathComponent(libName)
                    guard FileManager.default.fileExists(atPath: localCandidate.path) else {
                        continue
                    }

                    if oldPath.contains("@@HOMEBREW_PREFIX@@")
                        || oldPath.hasPrefix("/opt/homebrew/")
                        || oldPath.hasPrefix("/usr/local/")
                        || oldPath.hasPrefix("@rpath/") {
                        let newPath = "@loader_path/\(libName)"
                        let installNameProcess = Process()
                        installNameProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                        installNameProcess.arguments = ["-change", oldPath, newPath, fileURL.path]
                        try? installNameProcess.run()
                        installNameProcess.waitUntilExit()
                    }
                }

                // Fix the library's own ID
                let idProcess = Process()
                idProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                idProcess.arguments = ["-id", "@loader_path/\(fileURL.lastPathComponent)", fileURL.path]
                try? idProcess.run()
                idProcess.waitUntilExit()

                // Clear quarantine
                self.clearQuarantine(fileURL)
            }

            completion(.success(()))
        }
    }

    private func verifyInstallation(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let libPath = self.libMPVPath else {
                completion(.failure(MPVError.bundleNotFound))
                return
            }
            self.configureEnvironment(for: libPath)
            do {
                try MPVLibrary.shared.load(at: libPath.path)
                MPVLibrary.shared.unload()
                completion(.success(()))
            } catch {
                completion(.failure(MPVError.installVerificationFailed(error.localizedDescription)))
            }
        }
    }

    private func cleanupFailedInstall() {
        try? FileManager.default.removeItem(at: mpvDirectory)
        cachedLibPath = nil
        MPVLibrary.shared.unload()
    }

    private func currentArchKey() -> String {
        #if arch(arm64)
        if #available(macOS 26, *) {
            return "arm64_tahoe"
        } else if #available(macOS 15, *) {
            return "arm64_sequoia"
        } else {
            return "arm64_sonoma"
        }
        #else
        return "sonoma"
        #endif
    }

    /// Remove mpv installation
    func uninstall() throws {
        if FileManager.default.fileExists(atPath: mpvDirectory.path) {
            try FileManager.default.removeItem(at: mpvDirectory)
        }
        MPVLibrary.shared.unload()
        cachedLibPath = nil
    }

    /// Formats that require libmpv (not supported by AVFoundation)
    func requiresMPV(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["webm", "mkv", "ogv", "ogg", "flv", "f4v", "wmv", "vob", "divx", "asf"].contains(ext)
    }

    // MARK: - Paths

    var libMPVPath: URL? {
        if let cached = cachedLibPath, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let candidates: [URL] = [
            // Our bundled lib directory
            libDirectory.appendingPathComponent("libmpv.dylib"),
            libDirectory.appendingPathComponent("libmpv.2.dylib"),
            // System-wide installations
            URL(fileURLWithPath: "/Applications/IINA.app/Contents/Frameworks/libmpv.dylib"),
            URL(fileURLWithPath: "/opt/homebrew/lib/libmpv.dylib"),
            URL(fileURLWithPath: "/opt/homebrew/lib/libmpv.2.dylib"),
            URL(fileURLWithPath: "/usr/local/lib/libmpv.dylib"),
            URL(fileURLWithPath: "/usr/local/lib/libmpv.2.dylib")
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path.path) {
            cachedLibPath = path
            return path
        }

        // Search in our directory
        if let found = findLibMPV(in: mpvDirectory) {
            cachedLibPath = found
            return found
        }

        return nil
    }

    private func findLibMPV(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.hasPrefix("libmpv") && fileURL.pathExtension == "dylib" {
                return fileURL
            }
        }
        return nil
    }

    private func configureEnvironment(for libPath: URL) {
        var paths: [String] = []
        let libDir = libPath.deletingLastPathComponent().path
        paths.append(libDir)

        if let existing = getenv("DYLD_LIBRARY_PATH") {
            paths.append(String(cString: existing))
        }

        let joined = paths.joined(separator: ":")
        setenv("DYLD_LIBRARY_PATH", joined, 1)
    }

    private func clearQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}

enum MPVError: LocalizedError {
    case downloadFailed
    case extractFailed
    case bundleNotFound
    case installVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download libmpv."
        case .extractFailed:
            return "Failed to extract mpv package."
        case .bundleNotFound:
            return "libmpv not found in extracted package."
        case .installVerificationFailed(let message):
            return "libmpv installation could not be verified: \(message)"
        }
    }
}
