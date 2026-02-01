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
    case lineOverlay = "Line Overlay"
    case noir = "Noir"

    var id: String { rawValue }

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
        case .lineOverlay: return "pencil.and.outline"
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
        case .lineOverlay: return "Line drawing effect"
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
        }
    }
}
