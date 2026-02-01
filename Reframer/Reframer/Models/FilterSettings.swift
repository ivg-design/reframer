import Foundation

/// Settings for all video filters
struct FilterSettings: Codable, Equatable {
    // MARK: - Basic Adjustments
    var brightnessLevel: Double = 0.0  // -1.0 to 1.0 (0 = no change)
    var contrastLevel: Double = 1.0    // 0.25 to 4.0 (1 = no change)
    var saturationLevel: Double = 1.0  // 0.0 to 2.0 (0 = grayscale, 1 = normal)
    var exposure: Double = 0.0         // -3.0 to +3.0 EV stops

    // MARK: - Edge Detection
    var edgeIntensity: Double = 1.0  // 0.0 - 10.0

    // MARK: - Sharpen
    var sharpness: Double = 0.4  // 0.0 - 2.0

    // MARK: - Unsharp Mask
    var unsharpRadius: Double = 2.5  // 0.0 - 10.0
    var unsharpIntensity: Double = 0.5  // 0.0 - 2.0

    // MARK: - Monochrome
    var monochromeR: Double = 0.6  // 0.0 - 1.0
    var monochromeG: Double = 0.45  // 0.0 - 1.0
    var monochromeB: Double = 0.3  // 0.0 - 1.0
    var monochromeIntensity: Double = 1.0  // 0.0 - 1.0

    // MARK: - Line Art (simplified - noise/sharpness are fixed internally)
    var lineArtEdge: Double = 50.0       // 0.1 to 200 (line sensitivity)
    var lineArtThreshold: Double = 0.1   // 0.0 to 1.0 (line visibility cutoff)
    var lineArtContrast: Double = 50.0   // 1 to 200 (line darkness)

    // MARK: - Factory Methods

    /// Reset all settings to defaults
    static var defaults: FilterSettings {
        FilterSettings()
    }

    /// Preset for maximum edge emphasis (great for tracing)
    static var maxEdges: FilterSettings {
        var settings = FilterSettings()
        settings.edgeIntensity = 5.0
        return settings
    }

    /// Preset for high contrast viewing
    static var highContrast: FilterSettings {
        var settings = FilterSettings()
        settings.contrastLevel = 2.5
        settings.saturationLevel = 0.5
        return settings
    }

    /// Preset for line drawing style
    static var lineDrawing: FilterSettings {
        var settings = FilterSettings()
        settings.lineArtEdge = 75.0
        settings.lineArtContrast = 100.0
        return settings
    }
}
