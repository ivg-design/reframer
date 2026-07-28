import AppKit

/// Pure geometry helpers for restoring and attaching Reframer windows.
///
/// Keeping this logic independent of `NSScreen` makes multi-display behavior
/// deterministic and unit-testable.
enum WindowPlacement {
    static let panelGap: CGFloat = 10

    static func bestVisibleFrame(for frame: NSRect, among visibleFrames: [NSRect]) -> NSRect? {
        guard !visibleFrames.isEmpty else { return nil }

        let ranked = visibleFrames.map { visibleFrame -> (frame: NSRect, area: CGFloat) in
            let intersection = frame.intersection(visibleFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (visibleFrame, area)
        }

        if let bestIntersection = ranked.max(by: { $0.area < $1.area }),
           bestIntersection.area > 0 {
            return bestIntersection.frame
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return visibleFrames.min { lhs, rhs in
            squaredDistance(from: center, to: lhs) < squaredDistance(from: center, to: rhs)
        }
    }

    /// Clamps the video window while reserving room directly below it for the
    /// attached control window.
    static func clampMainFrame(
        _ frame: NSRect,
        visibleFrames: [NSRect],
        toolbarHeight: CGFloat,
        minimumSize: NSSize
    ) -> NSRect {
        guard !visibleFrames.isEmpty else { return frame }

        let safeToolbarHeight = max(0, toolbarHeight)
        let compositeFrame = NSRect(
            x: frame.minX,
            y: frame.minY - safeToolbarHeight,
            width: frame.width,
            height: frame.height + safeToolbarHeight
        )
        guard let visibleFrame = bestVisibleFrame(
            for: compositeFrame,
            among: visibleFrames
        ) else {
            return frame
        }

        let reservedToolbarHeight = min(
            safeToolbarHeight,
            max(0, visibleFrame.height - 1)
        )
        let availableMainHeight = max(1, visibleFrame.height - reservedToolbarHeight)

        var adjusted = frame.standardized
        adjusted.size.width = min(
            max(adjusted.width, min(minimumSize.width, visibleFrame.width)),
            visibleFrame.width
        )
        adjusted.size.height = min(
            max(adjusted.height, min(minimumSize.height, availableMainHeight)),
            availableMainHeight
        )

        adjusted.origin.x = clamp(
            adjusted.minX,
            lower: visibleFrame.minX,
            upper: visibleFrame.maxX - adjusted.width
        )
        adjusted.origin.y = clamp(
            adjusted.minY,
            lower: visibleFrame.minY + reservedToolbarHeight,
            upper: visibleFrame.maxY - adjusted.height
        )

        return adjusted
    }

    static func clampAuxiliaryFrame(
        _ frame: NSRect,
        visibleFrames: [NSRect],
        preferredScreenFrame: NSRect? = nil
    ) -> NSRect {
        guard !visibleFrames.isEmpty else { return frame }
        let visibleFrame = preferredScreenFrame
            ?? bestVisibleFrame(for: frame, among: visibleFrames)
            ?? visibleFrames[0]

        var adjusted = frame.standardized
        adjusted.size.width = min(max(1, adjusted.width), visibleFrame.width)
        adjusted.size.height = min(max(1, adjusted.height), visibleFrame.height)
        adjusted.origin.x = clamp(
            adjusted.minX,
            lower: visibleFrame.minX,
            upper: visibleFrame.maxX - adjusted.width
        )
        adjusted.origin.y = clamp(
            adjusted.minY,
            lower: visibleFrame.minY,
            upper: visibleFrame.maxY - adjusted.height
        )
        return adjusted
    }

    /// Places a panel on the right when it fits, then the left, then clamps it
    /// to the anchor's screen.
    static func attachedPanelFrame(
        size: NSSize,
        anchorFrame: NSRect,
        visibleFrames: [NSRect],
        gap: CGFloat = panelGap
    ) -> NSRect {
        guard !visibleFrames.isEmpty else {
            return NSRect(
                x: anchorFrame.maxX + gap,
                y: anchorFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        let visibleFrame = bestVisibleFrame(for: anchorFrame, among: visibleFrames)
            ?? visibleFrames[0]
        let y = anchorFrame.midY - size.height / 2
        let right = NSRect(
            x: anchorFrame.maxX + gap,
            y: y,
            width: size.width,
            height: size.height
        )
        if visibleFrame.contains(right) {
            return right
        }

        let left = NSRect(
            x: anchorFrame.minX - gap - size.width,
            y: y,
            width: size.width,
            height: size.height
        )
        if visibleFrame.contains(left) {
            return left
        }

        return clampAuxiliaryFrame(
            right,
            visibleFrames: visibleFrames,
            preferredScreenFrame: visibleFrame
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }

    private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let nearestX = clamp(point.x, lower: rect.minX, upper: rect.maxX)
        let nearestY = clamp(point.y, lower: rect.minY, upper: rect.maxY)
        let dx = point.x - nearestX
        let dy = point.y - nearestY
        return dx * dx + dy * dy
    }
}
