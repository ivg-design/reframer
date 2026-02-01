import Foundation

struct YouTubeStreamCandidate {
    let videoURL: URL
    let audioURL: URL?
    let qualityDescription: String
    let isAVFoundationCompatible: Bool
}

struct YouTubeStreamSelection {
    let title: String?
    let headers: [String: String]?
    let primary: YouTubeStreamCandidate
    let fallbackCombined: YouTubeStreamCandidate?
}

enum YouTubeResolverError: LocalizedError {
    case invalidURL
    case toolDownloadFailed
    case toolExecutionFailed(String)
    case noPlayableFormats

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid YouTube URL."
        case .toolDownloadFailed:
            return "Failed to download yt-dlp."
        case .toolExecutionFailed(let message):
            return "yt-dlp failed: \(message)"
        case .noPlayableFormats:
            return "No playable formats were found."
        }
    }
}

final class YouTubeResolver {
    static let shared = YouTubeResolver()

    // Use macOS standalone binary (no Python dependency)
    private let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    private var toolsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Reframer/Tools", isDirectory: true)
    }

    private var ytDlpPath: URL {
        toolsDirectory.appendingPathComponent("yt-dlp")
    }

    func resolve(url: URL, completion: @escaping (Result<YouTubeStreamSelection, Error>) -> Void) {
        guard url.scheme != nil else {
            completion(.failure(YouTubeResolverError.invalidURL))
            return
        }

        ensureYtDlp { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self?.fetchFormats(url: url, completion: completion)
            }
        }
    }

    private func ensureYtDlp(completion: @escaping (Result<Void, Error>) -> Void) {
        if FileManager.default.fileExists(atPath: ytDlpPath.path) {
            completion(.success(()))
            return
        }

        do {
            try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        let task = URLSession.shared.downloadTask(with: ytDlpURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }
            if let error = error {
                print("YouTubeResolver: yt-dlp download error - \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            // Validate HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                print("YouTubeResolver: yt-dlp download HTTP status: \(httpResponse.statusCode)")
                print("YouTubeResolver: Final URL: \(httpResponse.url?.absoluteString ?? "unknown")")
                guard httpResponse.statusCode == 200 else {
                    print("YouTubeResolver: yt-dlp download failed with HTTP \(httpResponse.statusCode)")
                    DispatchQueue.main.async { completion(.failure(YouTubeResolverError.toolDownloadFailed)) }
                    return
                }
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(.failure(YouTubeResolverError.toolDownloadFailed)) }
                return
            }

            // Validate downloaded file size (yt-dlp binary should be at least 1MB)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
               let fileSize = attrs[.size] as? Int64 {
                print("YouTubeResolver: Downloaded yt-dlp size: \(fileSize / 1024) KB")
                if fileSize < 1_000_000 {  // Less than 1MB is suspicious
                    print("YouTubeResolver: Downloaded file too small")
                    DispatchQueue.main.async { completion(.failure(YouTubeResolverError.toolDownloadFailed)) }
                    return
                }
            }

            do {
                if FileManager.default.fileExists(atPath: self.ytDlpPath.path) {
                    try FileManager.default.removeItem(at: self.ytDlpPath)
                }
                try FileManager.default.moveItem(at: tempURL, to: self.ytDlpPath)
                try self.makeExecutable(self.ytDlpPath)
                self.clearQuarantine(self.ytDlpPath)
                print("YouTubeResolver: yt-dlp installed at \(self.ytDlpPath.path)")
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                print("YouTubeResolver: Failed to install yt-dlp - \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    private func makeExecutable(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", url.path]
        try process.run()
        process.waitUntilExit()
    }

    private func clearQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private func fetchFormats(url: URL, completion: @escaping (Result<YouTubeStreamSelection, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = self.ytDlpPath
            // Add --no-warnings to suppress warning messages that could corrupt JSON output
            process.arguments = ["--no-warnings", "--no-playlist", "--dump-single-json", url.absoluteString]

            // Separate stdout (JSON) from stderr (errors/warnings)
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                // Log stderr for debugging
                if !stderrData.isEmpty {
                    let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                    print("YouTubeResolver: yt-dlp stderr: \(stderrStr.prefix(500))")
                }

                guard process.terminationStatus == 0 else {
                    // On failure, show stderr (errors) or stdout if stderr is empty
                    let errorData = stderrData.isEmpty ? stdoutData : stderrData
                    let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        completion(.failure(YouTubeResolverError.toolExecutionFailed(message)))
                    }
                    return
                }

                // Parse stdout as JSON (should be clean JSON without warnings)
                let selection = try self.selectionFromJSONData(stdoutData)
                DispatchQueue.main.async {
                    completion(.success(selection))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func selectionFromJSONData(_ data: Data) throws -> YouTubeStreamSelection {
        // Provide more detailed error for debugging
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            // If JSON parsing fails, show what yt-dlp actually returned
            let rawOutput = String(data: data, encoding: .utf8) ?? "(unable to decode output)"
            let preview = rawOutput.prefix(500)
            throw YouTubeResolverError.toolExecutionFailed("Invalid JSON response: \(preview)")
        }

        guard let dict = json as? [String: Any],
              let formats = dict["formats"] as? [[String: Any]] else {
            // Check if there's an error message in the response
            if let dict = json as? [String: Any], let error = dict["error"] as? String {
                throw YouTubeResolverError.toolExecutionFailed(error)
            }
            throw YouTubeResolverError.noPlayableFormats
        }

        let title = dict["title"] as? String
        let headers = dict["http_headers"] as? [String: String]
        let formatInfos = formats.compactMap { FormatInfo(dict: $0) }

        guard let selection = selectBest(formats: formatInfos, headers: headers, title: title) else {
            throw YouTubeResolverError.noPlayableFormats
        }

        return selection
    }

    private func selectBest(formats: [FormatInfo], headers: [String: String]?, title: String?) -> YouTubeStreamSelection? {
        let combined = formats.filter { $0.hasVideo && $0.hasAudio }
        let videoOnly = formats.filter { $0.hasVideo && !$0.hasAudio }
        let audioOnly = formats.filter { $0.hasAudio && !$0.hasVideo }

        // Filter out AV1 formats - VLC 3.0.x can't decode them reliably
        let combinedNoAV1 = combined.filter { !$0.isAV1 }
        let videoOnlyNoAV1 = videoOnly.filter { !$0.isAV1 }

        // AVFoundation compatible (H.264/HEVC in MP4)
        let bestAVCombined = combinedNoAV1.filter { $0.isAVFoundationCompatibleCombined }.max(by: formatSort)
        let bestAVVideo = videoOnlyNoAV1.filter { $0.isAVFoundationCompatibleVideo }.max(by: formatSort)
        let bestAVAudio = audioOnly.filter { $0.isAVFoundationCompatibleAudio }.max(by: formatSort)

        // VLC compatible (VP8/VP9 WebM, excluding AV1)
        let bestVLCCombined = combinedNoAV1.filter { $0.isVLCCompatible }.max(by: formatSort)
        let bestVLCVideo = videoOnlyNoAV1.filter { $0.isVLCCompatible }.max(by: formatSort)

        // Log available formats for debugging
        print("YouTubeResolver: Found \(formats.count) formats total")
        print("YouTubeResolver: AV1 formats: \(formats.filter { $0.isAV1 }.count) (excluded)")
        print("YouTubeResolver: AVFoundation-compatible: \(videoOnlyNoAV1.filter { $0.isAVFoundationCompatibleVideo }.count) video, \(audioOnly.filter { $0.isAVFoundationCompatibleAudio }.count) audio")
        print("YouTubeResolver: VLC-compatible (VP8/VP9): \(videoOnlyNoAV1.filter { $0.isVPx }.count) video")

        // Primary: AVFoundation compatible
        let avCandidate: YouTubeStreamCandidate? = {
            if let video = bestAVVideo, let audio = bestAVAudio {
                return YouTubeStreamCandidate(
                    videoURL: video.url,
                    audioURL: audio.url,
                    qualityDescription: "\(video.height)p \(video.vcodec)",
                    isAVFoundationCompatible: true
                )
            }
            if let combined = bestAVCombined {
                return YouTubeStreamCandidate(
                    videoURL: combined.url,
                    audioURL: nil,
                    qualityDescription: "\(combined.height)p \(combined.vcodec)",
                    isAVFoundationCompatible: true
                )
            }
            return nil
        }()

        // Fallback: VLC compatible (VP8/VP9 WebM) - NOT AV1
        let vlcCandidate: YouTubeStreamCandidate? = {
            if let video = bestVLCVideo, let audio = bestAVAudio {
                return YouTubeStreamCandidate(
                    videoURL: video.url,
                    audioURL: audio.url,
                    qualityDescription: "\(video.height)p \(video.vcodec)",
                    isAVFoundationCompatible: false
                )
            }
            if let combined = bestVLCCombined {
                return YouTubeStreamCandidate(
                    videoURL: combined.url,
                    audioURL: nil,
                    qualityDescription: "\(combined.height)p \(combined.vcodec)",
                    isAVFoundationCompatible: false
                )
            }
            return nil
        }()

        // Return best available option
        if let avCandidate = avCandidate {
            print("YouTubeResolver: Selected AVFoundation-compatible stream: \(avCandidate.qualityDescription)")
            return YouTubeStreamSelection(
                title: title,
                headers: headers,
                primary: avCandidate,
                fallbackCombined: vlcCandidate  // VLC fallback (VP8/VP9, no AV1)
            )
        }

        if let vlcCandidate = vlcCandidate {
            print("YouTubeResolver: Selected VLC-compatible stream (VP8/VP9): \(vlcCandidate.qualityDescription)")
            return YouTubeStreamSelection(
                title: title,
                headers: headers,
                primary: vlcCandidate,
                fallbackCombined: nil
            )
        }

        print("YouTubeResolver: No compatible formats found (all formats are AV1 or unsupported)")
        return nil
    }

    private func formatSort(_ lhs: FormatInfo, _ rhs: FormatInfo) -> Bool {
        if lhs.height != rhs.height {
            return lhs.height < rhs.height
        }
        return lhs.tbr < rhs.tbr
    }
}

private struct FormatInfo {
    let url: URL
    let ext: String
    let vcodec: String
    let acodec: String
    let height: Int
    let width: Int
    let tbr: Double

    var hasVideo: Bool { vcodec != "none" }
    var hasAudio: Bool { acodec != "none" }

    /// AV1 codec - VLC 3.0.x has unreliable AV1 support
    var isAV1: Bool {
        let codec = vcodec.lowercased()
        return codec.contains("av01") || codec.contains("av1")
    }

    /// VP8/VP9 codec - well supported by VLC
    var isVPx: Bool {
        let codec = vcodec.lowercased()
        return codec.contains("vp8") || codec.contains("vp9") || codec.contains("vp08") || codec.contains("vp09")
    }

    /// VLC can play this format (VP8/VP9 WebM, but NOT AV1)
    var isVLCCompatible: Bool {
        // VLC handles VP8/VP9 in WebM well, but AV1 is unreliable
        if isAV1 { return false }
        if ext == "webm" && isVPx { return true }
        // VLC can also play H.264/HEVC
        return isAVFoundationCompatibleVideo
    }

    var isAVFoundationCompatibleVideo: Bool {
        guard ext == "mp4" || ext == "mov" else { return false }
        let codec = vcodec.lowercased()
        return codec.contains("avc1") || codec.contains("h264") || codec.contains("hvc1") || codec.contains("hev1")
    }

    var isAVFoundationCompatibleAudio: Bool {
        guard ext == "m4a" || ext == "mp4" else { return false }
        let codec = acodec.lowercased()
        return codec.contains("mp4a") || codec.contains("aac")
    }

    var isAVFoundationCompatibleCombined: Bool {
        isAVFoundationCompatibleVideo && isAVFoundationCompatibleAudio
    }

    init?(dict: [String: Any]) {
        guard let urlString = dict["url"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        self.url = url
        self.ext = (dict["ext"] as? String) ?? ""
        self.vcodec = (dict["vcodec"] as? String) ?? "none"
        self.acodec = (dict["acodec"] as? String) ?? "none"
        self.height = dict["height"] as? Int ?? 0
        self.width = dict["width"] as? Int ?? 0
        self.tbr = dict["tbr"] as? Double ?? 0
    }
}
