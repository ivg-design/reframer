import AVFoundation
import UniformTypeIdentifiers

enum VideoPreflightError: LocalizedError {
    case unsupportedExtension(String)
    case missingFile
    case unreadableFile
    case notPlayable
    case protectedContent
    case noVideoTrack
    case invalidDuration
    case invalidVideoDimensions

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let ext):
            return ext.isEmpty
                ? "Choose an MP4, M4V, or MOV video."
                : ".\(ext.uppercased()) is not supported. Choose an MP4, M4V, or MOV video."
        case .missingFile:
            return "The selected video no longer exists."
        case .unreadableFile:
            return "Reframer cannot read the selected video. Check its file permissions."
        case .notPlayable:
            return "AVFoundation cannot play this file's video codec or media data."
        case .protectedContent:
            return "Protected video cannot be used as a reference overlay."
        case .noVideoTrack:
            return "The selected file does not contain a playable video track."
        case .invalidDuration:
            return "The selected video does not have a valid duration."
        case .invalidVideoDimensions:
            return "The selected video does not have valid display dimensions."
        }
    }
}

struct VideoFormats {
    static let supportedExtensions = ["mp4", "m4v", "mov"]

    static let supportedTypes: [UTType] = {
        var types: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        if let m4v = UTType("com.apple.m4v-video") {
            types.append(m4v)
        }
        return types
    }()

    static let displayString = "MP4 • M4V • MOV"

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }

        // A non-existent URL (for example, before a save/open operation or in
        // a unit test) is validated by extension. Existing files also have
        // their declared type checked so renamed non-video files are rejected.
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return true
        }
        return isSupported(contentType: contentType)
    }

    static func isSupported(contentType: UTType) -> Bool {
        supportedTypes.contains { contentType.conforms(to: $0) }
    }

    /// Validates the actual local asset before the UI declares it loaded.
    static func preflight(_ url: URL) async throws -> AVURLAsset {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw VideoPreflightError.unsupportedExtension(ext)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoPreflightError.missingFile
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw VideoPreflightError.unreadableFile
        }

        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw VideoPreflightError.notPlayable
        }
        guard try await !asset.load(.hasProtectedContent) else {
            throw VideoPreflightError.protectedContent
        }
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else {
            throw VideoPreflightError.noVideoTrack
        }
        return asset
    }
}
