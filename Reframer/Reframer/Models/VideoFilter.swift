import Foundation
import CoreImage

/// Available video filters for reference overlay work
enum VideoFilter: String, CaseIterable, Identifiable {
    case brightness = "Brightness"
    case contrast = "Contrast"
    case saturation = "Saturation"
    case exposure = "Exposure"
    case edges = "Edges"
    case sharpen = "Sharpen"
    case unsharpMask = "Unsharp Mask"
    case monochrome = "Monochrome"
    case invert = "Invert"
    case lineArt = "Line Art"
    case noir = "Noir"

    var id: String { rawValue }

    /// Whether this filter is "simple" (0-1 slider) and available in quick dropdown
    var isSimpleFilter: Bool {
        switch self {
        case .brightness, .contrast, .saturation, .exposure, .edges, .sharpen, .invert, .noir:
            return true
        case .unsharpMask, .monochrome, .lineArt:
            return false  // Complex filters with multiple parameters
        }
    }

    /// Simple filters available in dropdown menu
    static var simpleFilters: [VideoFilter] {
        allCases.filter { $0.isSimpleFilter }
    }

    /// Parameter range for quick filter slider (min, max, default)
    var parameterRange: (min: Double, max: Double, defaultValue: Double) {
        switch self {
        case .brightness: return (-1.0, 1.0, 0.0)
        case .contrast: return (0.25, 4.0, 1.0)
        case .saturation: return (0.0, 2.0, 1.0)
        case .exposure: return (-3.0, 3.0, 0.0)
        case .edges: return (0.0, 10.0, 1.0)
        case .sharpen: return (0.0, 2.0, 0.4)
        case .invert, .noir: return (0.0, 1.0, 1.0)  // No parameter, but need range
        case .unsharpMask: return (0.0, 10.0, 2.5)  // Uses radius as primary
        case .monochrome: return (0.0, 1.0, 1.0)    // Uses intensity as primary
        case .lineArt: return (0.1, 200.0, 50.0)    // Uses edge as primary
        }
    }

    /// Create filter using quick filter value (normalized 0-1)
    func createQuickFilter(normalizedValue: Double) -> CIFilter? {
        let range = parameterRange
        let actualValue = range.min + (normalizedValue * (range.max - range.min))

        switch self {
        case .brightness:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(actualValue, forKey: kCIInputBrightnessKey)
            filter?.setValue(1.0, forKey: kCIInputContrastKey)
            filter?.setValue(1.0, forKey: kCIInputSaturationKey)
            return filter

        case .contrast:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(0.0, forKey: kCIInputBrightnessKey)
            filter?.setValue(actualValue, forKey: kCIInputContrastKey)
            filter?.setValue(1.0, forKey: kCIInputSaturationKey)
            return filter

        case .saturation:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(0.0, forKey: kCIInputBrightnessKey)
            filter?.setValue(1.0, forKey: kCIInputContrastKey)
            filter?.setValue(actualValue, forKey: kCIInputSaturationKey)
            return filter

        case .exposure:
            let filter = CIFilter(name: "CIExposureAdjust")
            filter?.setValue(actualValue, forKey: kCIInputEVKey)
            return filter

        case .edges:
            let filter = CIFilter(name: "CIEdges")
            filter?.setValue(actualValue, forKey: kCIInputIntensityKey)
            return filter

        case .sharpen:
            let filter = CIFilter(name: "CISharpenLuminance")
            filter?.setValue(actualValue, forKey: kCIInputSharpnessKey)
            return filter

        case .invert:
            return CIFilter(name: "CIColorInvert")

        case .noir:
            return CIFilter(name: "CIPhotoEffectNoir")

        default:
            return nil  // Complex filters not available in quick mode
        }
    }

    /// SF Symbol name for the filter
    var iconName: String {
        switch self {
        case .brightness: return "sun.max"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop.fill"
        case .exposure: return "plusminus.circle"
        case .edges: return "square.3.layers.3d.down.left"
        case .sharpen: return "triangle"
        case .unsharpMask: return "circle.hexagongrid"
        case .monochrome: return "paintpalette"
        case .invert: return "circle.lefthalf.striped.horizontal.inverse"
        case .lineArt: return "scribble.variable"
        case .noir: return "moon.fill"
        }
    }

    /// Short description of the filter
    var description: String {
        switch self {
        case .brightness: return "Adjust image brightness"
        case .contrast: return "Adjust image contrast"
        case .saturation: return "Adjust color intensity"
        case .exposure: return "Adjust exposure (EV stops)"
        case .edges: return "Edge detection for tracing"
        case .sharpen: return "Enhance edge sharpness"
        case .unsharpMask: return "Professional sharpening"
        case .monochrome: return "Sepia/tint effect"
        case .invert: return "Invert all colors"
        case .lineArt: return "Line drawing (can overlay)"
        case .noir: return "B&W film effect"
        }
    }

    /// Create the CIFilter for this filter type with current settings
    func createFilter(settings: FilterSettings) -> CIFilter? {
        switch self {
        case .brightness:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(settings.brightnessLevel, forKey: kCIInputBrightnessKey)
            filter?.setValue(1.0, forKey: kCIInputContrastKey)
            filter?.setValue(1.0, forKey: kCIInputSaturationKey)
            return filter

        case .contrast:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(0.0, forKey: kCIInputBrightnessKey)
            filter?.setValue(settings.contrastLevel, forKey: kCIInputContrastKey)
            filter?.setValue(1.0, forKey: kCIInputSaturationKey)
            return filter

        case .saturation:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(0.0, forKey: kCIInputBrightnessKey)
            filter?.setValue(1.0, forKey: kCIInputContrastKey)
            filter?.setValue(settings.saturationLevel, forKey: kCIInputSaturationKey)
            return filter

        case .exposure:
            let filter = CIFilter(name: "CIExposureAdjust")
            filter?.setValue(settings.exposure, forKey: kCIInputEVKey)
            return filter

        case .edges:
            let filter = CIFilter(name: "CIEdges")
            filter?.setValue(settings.edgeIntensity, forKey: kCIInputIntensityKey)
            return filter

        case .sharpen:
            let filter = CIFilter(name: "CISharpenLuminance")
            filter?.setValue(settings.sharpness, forKey: kCIInputSharpnessKey)
            return filter

        case .unsharpMask:
            let filter = CIFilter(name: "CIUnsharpMask")
            filter?.setValue(settings.unsharpRadius, forKey: kCIInputRadiusKey)
            filter?.setValue(settings.unsharpIntensity, forKey: kCIInputIntensityKey)
            return filter

        case .monochrome:
            let filter = CIFilter(name: "CIColorMonochrome")
            filter?.setValue(CIColor(red: CGFloat(settings.monochromeR),
                                     green: CGFloat(settings.monochromeG),
                                     blue: CGFloat(settings.monochromeB)),
                            forKey: kCIInputColorKey)
            filter?.setValue(settings.monochromeIntensity, forKey: kCIInputIntensityKey)
            return filter

        case .invert:
            return CIFilter(name: "CIColorInvert")

        case .lineArt:
            let filter = CIFilter(name: "CILineOverlay")
            // Simplified parameters with sensible defaults
            filter?.setValue(0.07, forKey: "inputNRNoiseLevel")  // Fixed - noise reduction
            filter?.setValue(0.71, forKey: "inputNRSharpness")   // Fixed - sharpness
            filter?.setValue(settings.lineArtEdge, forKey: "inputEdgeIntensity")
            filter?.setValue(settings.lineArtThreshold, forKey: "inputThreshold")
            filter?.setValue(settings.lineArtContrast, forKey: "inputContrast")
            return filter

        case .noir:
            return CIFilter(name: "CIPhotoEffectNoir")
        }
    }
}
