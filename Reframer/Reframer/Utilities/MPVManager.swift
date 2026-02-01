import Foundation
import os.log
import Darwin

/// Manages libmpv installation and loading for extended format support
final class MPVManager {
    static let shared = MPVManager()

    private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.reframer", category: "MPVManager")

    private let mpvDownloadURLArm64 = URL(string: "https://laboratory.stolendata.net/~djinn/mpv_osx/mpv-arm64-latest.tar.gz")!
    private let mpvDownloadURLIntel = URL(string: "https://laboratory.stolendata.net/~djinn/mpv_osx/mpv-latest.tar.gz")!

    private var mpvDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Reframer/MPV", isDirectory: true)
    }

    var installDirectory: URL {
        mpvDirectory
    }

    private var mpvAppPath: URL {
        mpvDirectory.appendingPathComponent("mpv.app", isDirectory: true)
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

    /// Download and install mpv (bundled libmpv)
    func install(progressHandler: @escaping (Double, String) -> Void,
                 completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try FileManager.default.createDirectory(at: mpvDirectory, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        let downloadURL = currentDownloadURL()
        progressHandler(0.0, "Downloading libmpv…")
        os_log("MPV: Starting download from %{public}@", log: log, type: .info, downloadURL.absoluteString)

        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                os_log("MPV: Download error - %{public}@", log: self.log, type: .error, error.localizedDescription)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                os_log("MPV: Download HTTP status %{public}d", log: self.log, type: .info, httpResponse.statusCode)
                guard httpResponse.statusCode == 200 else {
                    DispatchQueue.main.async { completion(.failure(MPVError.downloadFailed)) }
                    return
                }
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(.failure(MPVError.downloadFailed)) }
                return
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
               let fileSize = attrs[.size] as? Int64 {
                os_log("MPV: Downloaded size %{public}.2f MB", log: self.log, type: .info, Double(fileSize) / 1024.0 / 1024.0)
                if fileSize < 10_000_000 { // <10MB is suspicious
                    DispatchQueue.main.async { completion(.failure(MPVError.downloadFailed)) }
                    return
                }
            }

            DispatchQueue.main.async { progressHandler(0.5, "Extracting libmpv…") }

            self.extractMPV(tempURL: tempURL) { result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        progressHandler(1.0, "Installation complete")
                        completion(.success(()))
                    }
                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }

        let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                progressHandler(progress.fractionCompleted * 0.5, "Downloading libmpv…")
            }
        }

        task.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
            _ = observation
        }
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

    private func currentDownloadURL() -> URL {
        #if arch(arm64)
        return mpvDownloadURLArm64
        #else
        return mpvDownloadURLIntel
        #endif
    }

    var libMPVPath: URL? {
        if let cached = cachedLibPath, FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let candidates: [URL] = [
            mpvAppPath.appendingPathComponent("Contents/MacOS/libmpv.dylib"),
            mpvAppPath.appendingPathComponent("Contents/Frameworks/libmpv.dylib"),
            URL(fileURLWithPath: "/Applications/mpv.app/Contents/MacOS/libmpv.dylib"),
            URL(fileURLWithPath: "/Applications/mpv.app/Contents/Frameworks/libmpv.dylib"),
            URL(fileURLWithPath: "/Applications/IINA.app/Contents/Frameworks/libmpv.dylib"),
            URL(fileURLWithPath: "/opt/homebrew/lib/libmpv.dylib"),
            URL(fileURLWithPath: "/usr/local/lib/libmpv.dylib")
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path.path) {
            cachedLibPath = path
            return path
        }

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
            if fileURL.lastPathComponent == "libmpv.dylib" {
                return fileURL
            }
        }
        return nil
    }

    private func configureEnvironment(for libPath: URL) {
        var paths: [String] = []
        let libDir = libPath.deletingLastPathComponent().path
        paths.append(libDir)

        let frameworksDir = libPath.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks")
        if FileManager.default.fileExists(atPath: frameworksDir.path) {
            paths.append(frameworksDir.path)
        }

        if let existing = getenv("DYLD_LIBRARY_PATH") {
            paths.append(String(cString: existing))
        }

        let joined = paths.joined(separator: ":")
        setenv("DYLD_LIBRARY_PATH", joined, 1)
    }

    // MARK: - Extraction

    private func extractMPV(tempURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("MPVExtract-\(UUID().uuidString)")

            do {
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let tarProcess = Process()
                tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tarProcess.arguments = ["-xf", tempURL.path, "-C", extractDir.path]
                let errorPipe = Pipe()
                tarProcess.standardError = errorPipe
                try tarProcess.run()
                tarProcess.waitUntilExit()

                if tarProcess.terminationStatus != 0 {
                    let errorStr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    os_log("MPV: tar extraction failed: %{public}@", log: self.log, type: .error, errorStr)
                    throw MPVError.extractFailed
                }

                if FileManager.default.fileExists(atPath: self.mpvAppPath.path) {
                    try FileManager.default.removeItem(at: self.mpvAppPath)
                }

                // Find mpv.app inside extracted directory
                guard let appURL = self.findMPVApp(in: extractDir) else {
                    throw MPVError.bundleNotFound
                }

                try FileManager.default.moveItem(at: appURL, to: self.mpvAppPath)
                self.clearQuarantine(self.mpvAppPath)

                if self.libMPVPath == nil {
                    throw MPVError.bundleNotFound
                }

                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func findMPVApp(in root: URL) -> URL? {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("mpv.app").path) {
            return root.appendingPathComponent("mpv.app")
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "mpv.app" {
                return fileURL
            }
        }
        return nil
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

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download libmpv."
        case .extractFailed:
            return "Failed to extract mpv package."
        case .bundleNotFound:
            return "libmpv not found in extracted package."
        }
    }
}
