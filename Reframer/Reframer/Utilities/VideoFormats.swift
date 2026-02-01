import UniformTypeIdentifiers
import AVFoundation

struct VideoFormats {
    /// All supported video types for file open dialog and drag-drop
    static let supportedTypes: [UTType] = buildSupportedTypes()

    private static func buildSupportedTypes() -> [UTType] {
        var types: [UTType] = []

        // Standard formats
        types.append(.mpeg4Movie)
        types.append(.quickTimeMovie)
        types.append(.avi)
        types.append(.movie)

        // M4V
        addType(&types, "com.apple.m4v-video")

        // Apple ProRes variants
        addType(&types, "com.apple.prores")
        addType(&types, "com.apple.prores.4444")
        addType(&types, "com.apple.prores.422")
        addType(&types, "com.apple.prores.422.hq")
        addType(&types, "com.apple.prores.422.lt")
        addType(&types, "com.apple.prores.422.proxy")

        // H.264/AVC
        addType(&types, "public.h264")
        addType(&types, "public.avc")

        // H.265/HEVC
        addType(&types, "public.hevc")

        // AV1 (macOS 13+ with hardware support)
        addType(&types, "public.av1")
        addType(&types, "org.aomedia.av1")

        // WebM and Matroska (require VLCKit for playback)
        addType(&types, "org.webmproject.webm")
        addType(&types, "org.matroska.mkv")

        // MPEG formats
        addType(&types, "public.mpeg")
        addType(&types, "public.mpeg-2-video")
        addType(&types, "public.mpeg-4")

        // Other common formats
        addType(&types, "com.microsoft.windows-media-wmv")
        addType(&types, "public.3gpp")
        addType(&types, "public.3gpp2")

        return types
    }

    private static func addType(_ types: inout [UTType], _ identifier: String) {
        if let type = UTType(identifier) {
            types.append(type)
        }
    }

    /// File extensions for display and validation
    static let supportedExtensions: [String] = [
        "mp4", "m4v", "mov", "avi", "mkv", "webm",
        "mpeg", "mpg", "mts", "m2ts", "ts", "m2v",
        "wmv", "flv", "f4v", "ogv", "ogg",
        "3gp", "3g2", "divx", "vob", "asf"
    ]

    /// Check if a URL is a supported video format
    static func isSupported(_ url: URL) -> Bool {
        if let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            if isSupported(contentType: contentType) {
                return true
            }
        }

        let ext = url.pathExtension.lowercased()
        if supportedExtensions.contains(ext) {
            return true
        }

        if let type = UTType(filenameExtension: ext) {
            return isSupported(contentType: type)
        }

        return false
    }

    static func isSupported(contentType: UTType) -> Bool {
        for type in supportedTypes {
            if contentType.conforms(to: type) {
                return true
            }
        }

        if contentType.conforms(to: .movie) || contentType.conforms(to: .video) || contentType.conforms(to: .audiovisualContent) {
            return true
        }

        return false
    }

    /// Get display string for supported formats
    static let displayString = "MP4 • MOV • ProRes • H.264 • H.265 • AV1 • WebM • MKV • AVI"

    /// Check if AVFoundation can play this URL by probing asset tracks
    /// Returns true if playable by AVFoundation, false if VLC should be used
    static func canAVFoundationPlay(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)

        // Check if asset is playable at all
        do {
            let isPlayable = try await asset.load(.isPlayable)
            if !isPlayable {
                return false
            }
        } catch {
            return false
        }

        // Check video tracks for decodable formats
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else { return false }

            for track in videoTracks {
                let formats = try await track.load(.formatDescriptions)
                for format in formats {
                    let mediaSubType = CMFormatDescriptionGetMediaSubType(format)

                    // VP8, VP9, and some other codecs are not supported by AVFoundation
                    // FourCC codes: 'vp08' = VP8, 'vp09' = VP9
                    let vp8Code = fourCC("vp08")
                    let vp9Code = fourCC("vp09")

                    if mediaSubType == vp8Code || mediaSubType == vp9Code {
                        return false
                    }
                }
            }

            return true
        } catch {
            return false
        }
    }

    /// Convert a 4-character string to FourCharCode
    private static func fourCC(_ string: String) -> FourCharCode {
        let chars = Array(string.utf8)
        guard chars.count == 4 else { return 0 }
        return FourCharCode(chars[0]) << 24 | FourCharCode(chars[1]) << 16 | FourCharCode(chars[2]) << 8 | FourCharCode(chars[3])
    }
}
