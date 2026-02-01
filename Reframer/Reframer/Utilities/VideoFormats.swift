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
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Get display string for supported formats
    static let displayString = "MP4 • MOV • ProRes • H.264 • H.265 • AV1 • WebM • MKV • AVI"
}
