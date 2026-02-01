import Foundation
import AppKit

/// Manages VLCKit installation and loading for extended format support
class VLCKitManager {
    static let shared = VLCKitManager()

    // MARK: - Properties

    // VLCKit framework (Obj-C wrapper) - does NOT include plugins
    private let vlcKitURL = URL(string: "https://download.videolan.org/pub/cocoapods/prod/VLCKit-3.7.2-3e42ae47-79128878.tar.xz")!

    // Full VLC.app to get plugins (~49MB compressed)
    #if arch(arm64)
    private let vlcAppURL = URL(string: "https://get.videolan.org/vlc/3.0.23/macosx/vlc-3.0.23-arm64.dmg")!
    #else
    private let vlcAppURL = URL(string: "https://get.videolan.org/vlc/3.0.23/macosx/vlc-3.0.23-intel64.dmg")!
    #endif
    private let expectedVLCVersionPrefix = "3.0.23"

    private(set) var isLoaded = false
    private var vlcBundle: Bundle?

    /// Directory where VLC libs are stored
    var vlcDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Reframer/VLC", isDirectory: true)
    }

    /// Path to VLCKit framework
    var frameworkPath: URL {
        vlcDirectory.appendingPathComponent("VLCKit.framework", isDirectory: true)
    }

    /// Path to plugins directory INSIDE the framework (where VLCKit expects them)
    var pluginsPath: URL {
        frameworkPath.appendingPathComponent("Resources/plugins", isDirectory: true)
    }

    /// Path to Resources directory
    var resourcesPath: URL {
        frameworkPath.appendingPathComponent("Resources", isDirectory: true)
    }

    /// Check if VLC is fully installed (has framework AND plugins)
    var isInstalled: Bool {
        let frameworkExists = FileManager.default.fileExists(atPath: frameworkPath.path)
        let pluginsExist = FileManager.default.fileExists(atPath: pluginsPath.path)
        return frameworkExists && pluginsExist
    }

    /// Check if VLCKit is enabled in preferences
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "VLCKitEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "VLCKitEnabled") }
    }

    /// Check if VLCKit is ready to use (installed + enabled + loaded)
    var isReady: Bool {
        isInstalled && isEnabled && isLoaded
    }

    // MARK: - Initialization

    private init() {
        // Log installation status at startup
        logInstallationStatus()

        // Try to load VLCKit if already installed and enabled
        if isInstalled && isEnabled {
            loadFramework()
        }
    }

    private func logInstallationStatus() {
        print("VLCKit: === Installation Status ===")
        print("VLCKit: VLC directory: \(vlcDirectory.path)")
        print("VLCKit: Framework path: \(frameworkPath.path)")
        print("VLCKit: Framework exists: \(FileManager.default.fileExists(atPath: frameworkPath.path))")
        print("VLCKit: Plugins path: \(pluginsPath.path)")
        print("VLCKit: Plugins exist: \(FileManager.default.fileExists(atPath: pluginsPath.path))")

        if FileManager.default.fileExists(atPath: pluginsPath.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: pluginsPath.path) {
                print("VLCKit: Plugin folders: \(contents.count) items")
                print("VLCKit: Plugin contents: \(contents.prefix(10).joined(separator: ", "))\(contents.count > 10 ? "..." : "")")
            }
        }
        print("VLCKit: === End Status ===")
    }

    private func currentLibVLCVersion() -> String? {
        guard let libraryClass = NSClassFromString("VLCLibrary") as AnyObject? else { return nil }
        let sharedSel = NSSelectorFromString("sharedLibrary")
        guard let library = libraryClass.perform(sharedSel)?.takeUnretainedValue() as? NSObject else { return nil }

        if let version = library.value(forKey: "version") as? String {
            return version
        }

        let versionSel = NSSelectorFromString("version")
        if library.responds(to: versionSel),
           let version = library.perform(versionSel)?.takeUnretainedValue() as? String {
            return version
        }

        return nil
    }

    // MARK: - Installation

    /// Download and install VLC with plugins and VLCKit framework
    func install(progressHandler: @escaping (Double, String) -> Void,
                 completion: @escaping (Result<Void, Error>) -> Void) {

        // Create VLC directory
        do {
            try FileManager.default.createDirectory(at: vlcDirectory,
                                                    withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        // Step 1: Download VLCKit framework
        progressHandler(0.0, "Downloading VLCKit framework...")
        print("VLCKit: Starting VLCKit download from \(vlcKitURL)")

        let vlckitTask = URLSession.shared.downloadTask(with: vlcKitURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                print("VLCKit: VLCKit download error - \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(.failure(VLCKitError.downloadFailed)) }
                return
            }

            DispatchQueue.main.async {
                progressHandler(0.3, "Extracting VLCKit...")
            }

            // Extract VLCKit
            self.extractVLCKit(tempURL: tempURL) { result in
                switch result {
                case .success:
                    // Step 2: Download VLC.app for plugins
                    DispatchQueue.main.async {
                        progressHandler(0.4, "Downloading VLC plugins (~49MB)...")
                    }
                    self.downloadVLCPlugins(progressHandler: progressHandler, completion: completion)

                case .failure(let error):
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }

        let observation = vlckitTask.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                progressHandler(progress.fractionCompleted * 0.3, "Downloading VLCKit framework...")
            }
        }

        vlckitTask.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
            _ = observation
        }
    }

    private func extractVLCKit(tempURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("VLCKitExtract-\(UUID().uuidString)")

            do {
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                print("VLCKit: Extracting tar.xz from \(tempURL.path) to \(extractDir.path)")

                // Extract tar.xz
                let tarProcess = Process()
                tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tarProcess.arguments = ["-xf", tempURL.path, "-C", extractDir.path]
                let errorPipe = Pipe()
                tarProcess.standardError = errorPipe
                try tarProcess.run()
                tarProcess.waitUntilExit()

                if tarProcess.terminationStatus != 0 {
                    let errorStr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    print("VLCKit: tar extraction failed with code \(tarProcess.terminationStatus): \(errorStr)")
                    throw VLCKitError.extractFailed
                }
                print("VLCKit: tar extraction successful")

                // Find VLCKit.framework
                let binaryPackage = extractDir.appendingPathComponent("VLCKit - binary package")
                let xcframework = binaryPackage.appendingPathComponent("VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework")

                guard FileManager.default.fileExists(atPath: xcframework.path) else {
                    print("VLCKit: Framework not found at \(xcframework.path)")
                    // Try alternate path
                    let altPath = extractDir.appendingPathComponent("VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework")
                    if FileManager.default.fileExists(atPath: altPath.path) {
                        try self.copyFramework(from: altPath)
                    } else {
                        throw VLCKitError.frameworkNotFound
                    }
                    completion(.success(()))
                    return
                }

                try self.copyFramework(from: xcframework)

                // Cleanup
                try? FileManager.default.removeItem(at: extractDir)
                try? FileManager.default.removeItem(at: tempURL)

                print("VLCKit: VLCKit framework installed")
                completion(.success(()))

            } catch {
                print("VLCKit: VLCKit extraction failed - \(error)")
                try? FileManager.default.removeItem(at: extractDir)
                completion(.failure(error))
            }
        }
    }

    private func copyFramework(from source: URL) throws {
        // Remove existing framework
        if FileManager.default.fileExists(atPath: frameworkPath.path) {
            try FileManager.default.removeItem(at: frameworkPath)
        }

        // Copy framework
        try FileManager.default.copyItem(at: source, to: frameworkPath)
        print("VLCKit: Copied framework to \(frameworkPath.path)")

        // Create Resources directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: resourcesPath.path) {
            try FileManager.default.createDirectory(at: resourcesPath, withIntermediateDirectories: true)
        }
    }

    private func downloadVLCPlugins(progressHandler: @escaping (Double, String) -> Void,
                                     completion: @escaping (Result<Void, Error>) -> Void) {

        print("VLCKit: Starting VLC.app download from \(vlcAppURL)")

        let downloadTask = URLSession.shared.downloadTask(with: vlcAppURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                print("VLCKit: VLC download error - \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(.failure(VLCKitError.downloadFailed)) }
                return
            }

            DispatchQueue.main.async {
                progressHandler(0.8, "Extracting VLC plugins...")
            }

            self.extractPluginsFromDMG(tempURL: tempURL) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        // Validate installation
                        if self.validateInstallation() {
                            progressHandler(1.0, "Installation complete")
                            self.loadFramework()
                            completion(.success(()))
                        } else {
                            completion(.failure(VLCKitError.pluginsNotFound))
                        }

                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        }

        let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                progressHandler(0.4 + progress.fractionCompleted * 0.4, "Downloading VLC plugins (~49MB)...")
            }
        }

        downloadTask.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
            _ = observation
        }
    }

    private func extractPluginsFromDMG(tempURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("VLC-\(UUID().uuidString).dmg")

            do {
                try FileManager.default.moveItem(at: tempURL, to: dmgPath)

                let mountURL = try self.mountDMG(at: dmgPath)
                defer {
                    self.unmountDMG(at: mountURL)
                    try? FileManager.default.removeItem(at: dmgPath)
                }

                let vlcAppPath = mountURL.appendingPathComponent("VLC.app/Contents/MacOS")
                let sourcePlugins = vlcAppPath.appendingPathComponent("plugins")

                guard FileManager.default.fileExists(atPath: sourcePlugins.path) else {
                    print("VLCKit: Plugins not found in VLC.app at \(sourcePlugins.path)")
                    throw VLCKitError.pluginsNotFound
                }

                // Remove existing plugins
                if FileManager.default.fileExists(atPath: self.pluginsPath.path) {
                    try FileManager.default.removeItem(at: self.pluginsPath)
                }

                // Copy plugins to VLCKit.framework/Resources/plugins
                print("VLCKit: Copying plugins from \(sourcePlugins.path) to \(self.pluginsPath.path)")
                try FileManager.default.copyItem(at: sourcePlugins, to: self.pluginsPath)

                // Clear quarantine attributes
                let xattrProcess = Process()
                xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProcess.arguments = ["-cr", self.vlcDirectory.path]
                try? xattrProcess.run()
                xattrProcess.waitUntilExit()

                // Log what we installed
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: self.pluginsPath.path) {
                    print("VLCKit: Installed \(contents.count) plugin folders")
                }

                print("VLCKit: Plugins installation complete")
                completion(.success(()))

            } catch {
                print("VLCKit: Plugin extraction failed - \(error)")
                try? FileManager.default.removeItem(at: dmgPath)
                completion(.failure(error))
            }
        }
    }

    private func mountDMG(at dmgPath: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", dmgPath.path, "-plist", "-nobrowse", "-quiet"]
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            print("VLCKit: Failed to mount DMG - exit code \(process.terminationStatus): \(errorStr)")
            throw VLCKitError.extractFailed
        }

        do {
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            if let dict = plist as? [String: Any],
               let entities = dict["system-entities"] as? [[String: Any]] {
                for entity in entities {
                    if let mountPoint = entity["mount-point"] as? String {
                        print("VLCKit: DMG mounted at \(mountPoint)")
                        return URL(fileURLWithPath: mountPoint)
                    }
                }
            }
            print("VLCKit: Could not find mount point in plist response")
        } catch {
            print("VLCKit: Failed to parse hdiutil plist output: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                print("VLCKit: Raw hdiutil output: \(str.prefix(500))")
            }
            throw error
        }

        throw VLCKitError.extractFailed
    }

    private func unmountDMG(at mountURL: URL) {
        let hdiutilUnmount = Process()
        hdiutilUnmount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        hdiutilUnmount.arguments = ["detach", mountURL.path, "-quiet", "-force"]
        try? hdiutilUnmount.run()
        hdiutilUnmount.waitUntilExit()
    }

    private func validateInstallation() -> Bool {
        print("VLCKit: Validating installation...")

        // Check framework exists
        guard FileManager.default.fileExists(atPath: frameworkPath.path) else {
            print("VLCKit: VALIDATION FAILED - Framework not found")
            return false
        }

        // Check plugins exist
        guard FileManager.default.fileExists(atPath: pluginsPath.path) else {
            print("VLCKit: VALIDATION FAILED - Plugins directory not found")
            return false
        }

        // Check plugins have content
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: pluginsPath.path),
              !contents.isEmpty else {
            print("VLCKit: VALIDATION FAILED - Plugins directory is empty")
            return false
        }

        // Check for key plugins (search recursively)
        let keyPlugins = Set(["libmkv_plugin.dylib", "libvpx_plugin.dylib"])
        var foundPlugins = Set<String>()
        if let enumerator = FileManager.default.enumerator(at: pluginsPath, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if keyPlugins.contains(fileURL.lastPathComponent) {
                    foundPlugins.insert(fileURL.lastPathComponent)
                }
            }
        }
        for plugin in foundPlugins {
            print("VLCKit: Found key plugin: \(plugin)")
        }

        print("VLCKit: VALIDATION PASSED - \(contents.count) plugin files found")
        return true
    }

    // MARK: - Loading

    /// Load VLC libraries dynamically
    @discardableResult
    func loadFramework() -> Bool {
        guard !isLoaded else { return true }

        guard isInstalled else {
            print("VLCKit: Cannot load - not installed")
            return false
        }

        // CRITICAL: Set environment variables BEFORE loading VLCKit
        setenv("VLC_PLUGIN_PATH", pluginsPath.path, 1)
        setenv("VLC_DATA_PATH", resourcesPath.path, 1)
        print("VLCKit: Set VLC_PLUGIN_PATH = \(pluginsPath.path)")
        print("VLCKit: Set VLC_DATA_PATH = \(resourcesPath.path)")

        // Load VLCKit framework
        guard let bundle = Bundle(url: frameworkPath) else {
            print("VLCKit: Failed to create bundle for \(frameworkPath.path)")
            return false
        }

        do {
            try bundle.loadAndReturnError()
            vlcBundle = bundle
            isLoaded = true
            print("VLCKit: Successfully loaded VLCKit framework")

            // Log final status
            logInstallationStatus()
            if let version = currentLibVLCVersion() {
                print("VLCKit: libVLC version = \(version)")
                if !version.hasPrefix(expectedVLCVersionPrefix) {
                    print("VLCKit: WARNING - libVLC version does not match expected \(expectedVLCVersionPrefix). Plugins may fail to load.")
                }
            }

            return true
        } catch {
            print("VLCKit: Failed to load VLCKit - \(error)")
            return false
        }
    }

    /// Get the options to pass when creating VLCMediaPlayer
    /// These options create a private VLCLibrary instance
    func getLibraryOptions() -> [String] {
        return [
            "--codec=avcodec,all",         // Prefer software codecs
            "--no-videotoolbox",           // Disable Video Toolbox (doesn't support VP9)
            "--avcodec-hw=none",           // Disable hardware decode for codec fallback
            "--avcodec-skiploopfilter=0",  // Full quality decoding
            "--no-video-title-show",
            "--no-stats",
            "-vv"                          // Some verbosity for debugging
        ]
    }

    // MARK: - Uninstall

    /// Remove VLC
    func uninstall() throws {
        if FileManager.default.fileExists(atPath: vlcDirectory.path) {
            try FileManager.default.removeItem(at: vlcDirectory)
        }
        isEnabled = false
        isLoaded = false
        vlcBundle = nil
    }

    // MARK: - Format Support

    /// Formats that require VLC (not supported by AVFoundation)
    static let vlcOnlyExtensions = Set(["webm", "mkv", "ogv", "ogg", "flv", "wmv", "divx", "vob", "asf"])

    /// Check if a file requires VLC for playback
    func requiresVLCKit(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return Self.vlcOnlyExtensions.contains(ext)
    }

    /// Check if we can play a file (either AVFoundation or VLC)
    func canPlay(url: URL) -> Bool {
        if requiresVLCKit(url: url) {
            return isReady
        }
        return true  // AVFoundation can handle it
    }
}

// MARK: - Errors

enum VLCKitError: LocalizedError {
    case downloadFailed
    case extractFailed
    case frameworkNotFound
    case loadFailed
    case pluginsNotFound

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Failed to download VLC"
        case .extractFailed: return "Failed to extract VLC from disk image"
        case .frameworkNotFound: return "VLCKit framework not found"
        case .loadFailed: return "Failed to load VLC libraries"
        case .pluginsNotFound: return "VLC plugins not found - playback will fail"
        }
    }
}
