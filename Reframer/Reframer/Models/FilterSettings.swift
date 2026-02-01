import Foundation

/// Settings for all video filters
struct FilterSettings: Codable, Equatable {
    // MARK: - Edge Detection
    var edgeIntensity: Double = 1.0  // 0.0 - 10.0

    // MARK: - Sharpen
    var sharpness: Double = 0.4  // 0.0 - 2.0

    // MARK: - Unsharp Mask
    var unsharpRadius: Double = 2.5  // 0.0 - 10.0
    var unsharpIntensity: Double = 0.5  // 0.0 - 2.0

    // MARK: - Color Controls (Contrast filter)
    var brightness: Double = 0.0  // -1.0 - 1.0
    var contrast: Double = 1.5  // 0.25 - 4.0
    var saturation: Double = 1.0  // 0.0 - 2.0

    // MARK: - Monochrome
    var monochromeR: Double = 0.6  // 0.0 - 1.0
    var monochromeG: Double = 0.45  // 0.0 - 1.0
    var monochromeB: Double = 0.3  // 0.0 - 1.0
    var monochromeIntensity: Double = 1.0  // 0.0 - 1.0

    // MARK: - Line Overlay
    var lineOverlayNoise: Double = 0.07  // 0.0 - 0.1
    var lineOverlaySharpness: Double = 0.71  // 0.0 - 2.0
    var lineOverlayEdge: Double = 1.0  // 0.0 - 200.0
    var lineOverlayThreshold: Double = 0.1  // 0.0 - 1.0
    var lineOverlayContrast: Double = 50.0  // 0.25 - 200.0

    // MARK: - Exposure
    var exposure: Double = 1.0  // 0.0 - 3.0

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
        settings.contrast = 2.5
        settings.saturation = 0.5
        return settings
    }

    /// Preset for line drawing style
    static var lineDrawing: FilterSettings {
        var settings = FilterSettings()
        settings.lineOverlayEdge = 50.0
        settings.lineOverlayContrast = 75.0
        return settings
    }
}
