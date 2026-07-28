import AppKit

/// Pure geometry helpers for restoring and attaching Reframer windows.
///
/// Keeping this logic independent of `NSScreen` makes multi-display behavior
/// deterministic and unit-testable.
enum WindowPlacement {
    static let panelGap: CGFloat = 10

    static func isUsableFrame(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }

    static func bestVisibleFrame(for frame: NSRect, among visibleFrames: [NSRect]) -> NSRect? {
        let usableFrames = visibleFrames.filter(isUsableFrame)
        guard !usableFrames.isEmpty else { return nil }
        guard isUsableFrame(frame) else { return usableFrames[0] }

        let ranked = usableFrames.map { visibleFrame -> (frame: NSRect, area: CGFloat) in
            let intersection = frame.intersection(visibleFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            return (visibleFrame, area)
        }

        if let bestIntersection = ranked.max(by: { $0.area < $1.area }),
           bestIntersection.area > 0 {
            return bestIntersection.frame
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return usableFrames.min { lhs, rhs in
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
        let usableFrames = visibleFrames.filter(isUsableFrame)
        guard !usableFrames.isEmpty else { return frame }

        let safeToolbarHeight = toolbarHeight.isFinite ? max(0, toolbarHeight) : 0
        let safeMinimumSize = NSSize(
            width: finitePositive(minimumSize.width),
            height: finitePositive(minimumSize.height)
        )
        let candidateFrame: NSRect
        if isUsableFrame(frame) {
            candidateFrame = frame.standardized
        } else {
            let visibleFrame = usableFrames[0]
            let reservedToolbarHeight = min(
                safeToolbarHeight,
                max(0, visibleFrame.height - 1)
            )
            let availableMainHeight = max(1, visibleFrame.height - reservedToolbarHeight)
            let size = NSSize(
                width: min(safeMinimumSize.width, visibleFrame.width),
                height: min(safeMinimumSize.height, availableMainHeight)
            )
            candidateFrame = NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2 + reservedToolbarHeight / 2,
                width: size.width,
                height: size.height
            )
        }

        let compositeFrame = NSRect(
            x: candidateFrame.minX,
            y: candidateFrame.minY - safeToolbarHeight,
            width: candidateFrame.width,
            height: candidateFrame.height + safeToolbarHeight
        )
        guard let visibleFrame = bestVisibleFrame(
            for: compositeFrame,
            among: usableFrames
        ) else {
            return candidateFrame
        }

        let reservedToolbarHeight = min(
            safeToolbarHeight,
            max(0, visibleFrame.height - 1)
        )
        let availableMainHeight = max(1, visibleFrame.height - reservedToolbarHeight)

        var adjusted = candidateFrame
        adjusted.size.width = min(
            max(adjusted.width, min(safeMinimumSize.width, visibleFrame.width)),
            visibleFrame.width
        )
        adjusted.size.height = min(
            max(adjusted.height, min(safeMinimumSize.height, availableMainHeight)),
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
        let usableFrames = visibleFrames.filter(isUsableFrame)
        guard !usableFrames.isEmpty else { return frame }
        let preferredFrame = preferredScreenFrame.flatMap {
            isUsableFrame($0) ? $0 : nil
        }
        let visibleFrame = preferredFrame
            ?? bestVisibleFrame(for: frame, among: visibleFrames)
            ?? usableFrames[0]

        var adjusted: NSRect
        if isUsableFrame(frame) {
            adjusted = frame.standardized
        } else {
            adjusted = NSRect(
                x: visibleFrame.midX - 0.5,
                y: visibleFrame.midY - 0.5,
                width: 1,
                height: 1
            )
        }
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
        let usableFrames = visibleFrames.filter(isUsableFrame)
        let safeGap = gap.isFinite ? max(0, gap) : panelGap
        let safeSize = NSSize(
            width: finitePositive(size.width),
            height: finitePositive(size.height)
        )
        guard !usableFrames.isEmpty else {
            return NSRect(
                x: anchorFrame.maxX + safeGap,
                y: anchorFrame.midY - safeSize.height / 2,
                width: safeSize.width,
                height: safeSize.height
            )
        }

        let safeAnchorFrame = isUsableFrame(anchorFrame)
            ? anchorFrame.standardized
            : usableFrames[0]
        let visibleFrame = bestVisibleFrame(for: safeAnchorFrame, among: usableFrames)
            ?? usableFrames[0]
        let y = safeAnchorFrame.midY - safeSize.height / 2
        let right = NSRect(
            x: safeAnchorFrame.maxX + safeGap,
            y: y,
            width: safeSize.width,
            height: safeSize.height
        )
        if visibleFrame.contains(right) {
            return right
        }

        let left = NSRect(
            x: safeAnchorFrame.minX - safeGap - safeSize.width,
            y: y,
            width: safeSize.width,
            height: safeSize.height
        )
        if visibleFrame.contains(left) {
            return left
        }

        return clampAuxiliaryFrame(
            right,
            visibleFrames: usableFrames,
            preferredScreenFrame: visibleFrame
        )
    }

    private static func finitePositive(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return max(1, value)
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
