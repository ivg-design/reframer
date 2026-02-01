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

    private let ytDlpURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!

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

        let task = URLSession.shared.downloadTask(with: ytDlpURL) { [weak self] tempURL, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(.failure(YouTubeResolverError.toolDownloadFailed)) }
                return
            }
            do {
                if FileManager.default.fileExists(atPath: self.ytDlpPath.path) {
                    try FileManager.default.removeItem(at: self.ytDlpPath)
                }
                try FileManager.default.moveItem(at: tempURL, to: self.ytDlpPath)
                try self.makeExecutable(self.ytDlpPath)
                self.clearQuarantine(self.ytDlpPath)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
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
            process.arguments = ["--no-playlist", "--dump-single-json", url.absoluteString]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        completion(.failure(YouTubeResolverError.toolExecutionFailed(message)))
                    }
                    return
                }

                let selection = try self.selectionFromJSONData(data)
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
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = json as? [String: Any],
              let formats = dict["formats"] as? [[String: Any]] else {
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

        let bestCombined = combined.max(by: formatSort)
        let bestAVCombined = combined.filter { $0.isAVFoundationCompatibleCombined }.max(by: formatSort)
        let bestAVVideo = videoOnly.filter { $0.isAVFoundationCompatibleVideo }.max(by: formatSort)
        let bestAVAudio = audioOnly.filter { $0.isAVFoundationCompatibleAudio }.max(by: formatSort)

        let avCandidate: YouTubeStreamCandidate? = {
            if let video = bestAVVideo, let audio = bestAVAudio {
                return YouTubeStreamCandidate(
                    videoURL: video.url,
                    audioURL: audio.url,
                    qualityDescription: "\(video.height)x\(video.width) \(video.ext.uppercased())",
                    isAVFoundationCompatible: true
                )
            }
            if let combined = bestAVCombined {
                return YouTubeStreamCandidate(
                    videoURL: combined.url,
                    audioURL: nil,
                    qualityDescription: "\(combined.height)x\(combined.width) \(combined.ext.uppercased())",
                    isAVFoundationCompatible: true
                )
            }
            return nil
        }()

        let fallbackCombinedCandidate: YouTubeStreamCandidate? = {
            guard let combined = bestCombined else { return nil }
            return YouTubeStreamCandidate(
                videoURL: combined.url,
                audioURL: nil,
                qualityDescription: "\(combined.height)x\(combined.width) \(combined.ext.uppercased())",
                isAVFoundationCompatible: combined.isAVFoundationCompatibleCombined
            )
        }()

        if let avCandidate = avCandidate {
            return YouTubeStreamSelection(
                title: title,
                headers: headers,
                primary: avCandidate,
                fallbackCombined: fallbackCombinedCandidate
            )
        }

        if let fallback = fallbackCombinedCandidate {
            return YouTubeStreamSelection(
                title: title,
                headers: headers,
                primary: fallback,
                fallbackCombined: nil
            )
        }

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
