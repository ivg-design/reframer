import Foundation
import CoreImage

/// Available video filters for reference overlay work
enum VideoFilter: String, CaseIterable, Identifiable {
    case edges = "Edges"
    case sharpen = "Sharpen"
    case unsharpMask = "Unsharp Mask"
    case contrast = "High Contrast"
    case saturation = "Saturation"
    case monochrome = "Monochrome"
    case invert = "Invert"
    case lineOverlay = "Line Overlay"
    case noir = "Noir"
    case exposure = "Exposure"

    var id: String { rawValue }

    /// SF Symbol name for the filter
    var iconName: String {
        switch self {
        case .edges: return "square.3.layers.3d.down.left"
        case .sharpen: return "triangle"
        case .unsharpMask: return "circle.hexagongrid"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop.fill"
        case .monochrome: return "paintpalette"
        case .invert: return "circle.lefthalf.striped.horizontal.inverse"
        case .lineOverlay: return "pencil.and.outline"
        case .noir: return "moon.fill"
        case .exposure: return "sun.max"
        }
    }

    /// Short description of the filter
    var description: String {
        switch self {
        case .edges: return "Sobel edge detection - great for tracing"
        case .sharpen: return "Enhance edge sharpness"
        case .unsharpMask: return "Classic sharpening with radius control"
        case .contrast: return "Boost contrast for visibility"
        case .saturation: return "Adjust color intensity (0 = grayscale)"
        case .monochrome: return "Convert to single color"
        case .invert: return "Invert all colors"
        case .lineOverlay: return "Black and white line drawing"
        case .noir: return "High contrast black and white"
        case .exposure: return "Adjust brightness (negative = darker, positive = brighter)"
        }
    }

    /// Create the CIFilter for this filter type with current settings
    func createFilter(settings: FilterSettings) -> CIFilter? {
        switch self {
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

        case .contrast:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(settings.brightness, forKey: kCIInputBrightnessKey)
            filter?.setValue(settings.contrast, forKey: kCIInputContrastKey)
            filter?.setValue(1.0, forKey: kCIInputSaturationKey)  // Don't affect saturation
            return filter

        case .saturation:
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(0.0, forKey: kCIInputBrightnessKey)  // Don't affect brightness
            filter?.setValue(1.0, forKey: kCIInputContrastKey)    // Don't affect contrast
            filter?.setValue(settings.saturationLevel, forKey: kCIInputSaturationKey)
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

        case .lineOverlay:
            let filter = CIFilter(name: "CILineOverlay")
            filter?.setValue(settings.lineOverlayNoise, forKey: "inputNRNoiseLevel")
            filter?.setValue(settings.lineOverlaySharpness, forKey: "inputNRSharpness")
            filter?.setValue(settings.lineOverlayEdge, forKey: "inputEdgeIntensity")
            filter?.setValue(settings.lineOverlayThreshold, forKey: "inputThreshold")
            filter?.setValue(settings.lineOverlayContrast, forKey: "inputContrast")
            return filter

        case .noir:
            return CIFilter(name: "CIPhotoEffectNoir")

        case .exposure:
            let filter = CIFilter(name: "CIExposureAdjust")
            filter?.setValue(settings.exposure, forKey: kCIInputEVKey)
            return filter
        }
    }
}
