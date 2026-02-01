import Cocoa
import Combine

/// View that shows subtle glowing indicators on edges when mouse is near them
/// Helps users discover resize handles on the borderless window
class EdgeIndicatorView: NSView {

    // MARK: - Properties

    weak var videoState: VideoState? {
        didSet { bindState() }
    }

    private var cancellables = Set<AnyCancellable>()
    private var isMouseInView = false
    private var hoverTimer: Timer?
    private var activeEdge: Edge?

    private let glowWidth: CGFloat = 15  // Width of the glow gradient
    private let baseOpacity: Float = 0.08  // Very subtle base glow
    private let hoverOpacity: Float = 0.25  // Brighter when hovering
    private let hoverDelay: TimeInterval = 0.1  // 100ms delay before highlighting

    enum Edge {
        case top, left, right
    }

    // Gradient layers for soft glow effect
    private let topGlow = CAGradientLayer()
    private let leftGlow = CAGradientLayer()
    private let rightGlow = CAGradientLayer()

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        // Configure gradient layers for soft glow effect
        let glowColor = NSColor.white

        // Top glow - gradient from top edge inward
        topGlow.colors = [
            glowColor.withAlphaComponent(0.4).cgColor,
            glowColor.withAlphaComponent(0).cgColor
        ]
        topGlow.startPoint = CGPoint(x: 0.5, y: 1)  // Top
        topGlow.endPoint = CGPoint(x: 0.5, y: 0)    // Bottom
        topGlow.opacity = 0
        layer?.addSublayer(topGlow)

        // Left glow - gradient from left edge inward
        leftGlow.colors = [
            glowColor.withAlphaComponent(0.4).cgColor,
            glowColor.withAlphaComponent(0).cgColor
        ]
        leftGlow.startPoint = CGPoint(x: 0, y: 0.5)  // Left
        leftGlow.endPoint = CGPoint(x: 1, y: 0.5)    // Right
        leftGlow.opacity = 0
        layer?.addSublayer(leftGlow)

        // Right glow - gradient from right edge inward
        rightGlow.colors = [
            glowColor.withAlphaComponent(0.4).cgColor,
            glowColor.withAlphaComponent(0).cgColor
        ]
        rightGlow.startPoint = CGPoint(x: 1, y: 0.5)  // Right
        rightGlow.endPoint = CGPoint(x: 0, y: 0.5)    // Left
        rightGlow.opacity = 0
        layer?.addSublayer(rightGlow)

        updateTrackingAreas()
    }

    // MARK: - State Binding

    private func bindState() {
        cancellables.removeAll()
        guard let state = videoState else { return }

        // Show/hide based on lock state
        state.$isLocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLocked in
                self?.isHidden = isLocked
                if isLocked {
                    self?.hideAllGlows()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateGlowFrames()
    }

    private func updateGlowFrames() {
        let bounds = self.bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Top glow - full width, glowWidth tall, at top
        topGlow.frame = CGRect(
            x: 0,
            y: bounds.maxY - glowWidth,
            width: bounds.width,
            height: glowWidth
        )

        // Left glow - glowWidth wide, full height
        leftGlow.frame = CGRect(
            x: 0,
            y: 0,
            width: glowWidth,
            height: bounds.height
        )

        // Right glow - glowWidth wide, full height, at right
        rightGlow.frame = CGRect(
            x: bounds.maxX - glowWidth,
            y: 0,
            width: glowWidth,
            height: bounds.height
        )

        CATransaction.commit()
    }

    // MARK: - Mouse Tracking

    override func updateTrackingAreas() {
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard videoState?.isLocked == false else { return }
        isMouseInView = true
        showBaseGlows()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInView = false
        hoverTimer?.invalidate()
        hoverTimer = nil
        activeEdge = nil
        hideAllGlows()
    }

    override func mouseMoved(with event: NSEvent) {
        guard videoState?.isLocked == false, isMouseInView else { return }

        let location = convert(event.locationInWindow, from: nil)
        let edgeZone: CGFloat = 25  // Distance from edge to detect hover

        // Determine which edge (if any) the mouse is near
        var nearEdge: Edge?
        if location.y > bounds.maxY - edgeZone {
            nearEdge = .top
        } else if location.x < edgeZone {
            nearEdge = .left
        } else if location.x > bounds.maxX - edgeZone {
            nearEdge = .right
        }

        // If edge changed, reset the hover timer
        if nearEdge != activeEdge {
            hoverTimer?.invalidate()

            if let edge = nearEdge {
                // Start timer to highlight after delay
                hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
                    self?.highlightEdge(edge)
                }
            } else {
                // Not near any edge, show base glows
                showBaseGlows()
            }

            activeEdge = nearEdge
        }
    }

    // MARK: - Glow Animation

    private func showBaseGlows() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        topGlow.opacity = baseOpacity
        leftGlow.opacity = baseOpacity
        rightGlow.opacity = baseOpacity
        CATransaction.commit()
    }

    private func hideAllGlows() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        topGlow.opacity = 0
        leftGlow.opacity = 0
        rightGlow.opacity = 0
        CATransaction.commit()
    }

    private func highlightEdge(_ edge: Edge) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)

        // Reset all to base
        topGlow.opacity = baseOpacity
        leftGlow.opacity = baseOpacity
        rightGlow.opacity = baseOpacity

        // Highlight the active edge
        switch edge {
        case .top:
            topGlow.opacity = hoverOpacity
        case .left:
            leftGlow.opacity = hoverOpacity
        case .right:
            rightGlow.opacity = hoverOpacity
        }

        CATransaction.commit()
    }
}
