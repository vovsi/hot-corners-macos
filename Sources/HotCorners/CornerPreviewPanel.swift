import AppKit

/// A small floating card that appears near the screen corner the user is
/// hovering, showing which app will launch. Clicking it confirms the launch.
final class CornerPreviewPanel: NSPanel {
    var onConfirm: (() -> Void)?

    private let previewSize = NSSize(width: 220, height: 220)
    /// Gap kept between the card and the physical screen edges, so it reads
    /// as a floating card rather than merging into the screen bezel.
    private let edgeMargin: CGFloat = 14
    private let corner: Corner
    private let restingOrigin: NSPoint

    /// The panel's target on-screen frame — stable even while `frame` itself
    /// is mid-flight during the intro slide.
    var restingFrame: NSRect { NSRect(origin: restingOrigin, size: previewSize) }

    /// The resting frame stretched out to the two screen edges next to the
    /// corner, so there's no dead zone between the physical corner (where
    /// the hover started) and the inset card the pointer needs to reach.
    func hoverZone(in screenFrame: NSRect) -> NSRect {
        let resting = restingFrame
        switch corner {
        case .topLeft:
            return NSRect(x: screenFrame.minX, y: resting.minY, width: resting.maxX - screenFrame.minX, height: screenFrame.maxY - resting.minY)
        case .topRight:
            return NSRect(x: resting.minX, y: resting.minY, width: screenFrame.maxX - resting.minX, height: screenFrame.maxY - resting.minY)
        case .bottomLeft:
            return NSRect(x: screenFrame.minX, y: screenFrame.minY, width: resting.maxX - screenFrame.minX, height: resting.maxY - screenFrame.minY)
        case .bottomRight:
            return NSRect(x: resting.minX, y: screenFrame.minY, width: screenFrame.maxX - resting.minX, height: resting.maxY - screenFrame.minY)
        }
    }

    init(corner: Corner, icon: NSImage?, screenFrame: NSRect) {
        self.corner = corner
        let restingOrigin = CornerPreviewPanel.restingOrigin(for: corner, in: screenFrame, size: previewSize, margin: edgeMargin)
        let startOrigin = CornerPreviewPanel.offscreenOrigin(for: corner, restingOrigin: restingOrigin, size: previewSize)
        self.restingOrigin = restingOrigin

        super.init(
            contentRect: NSRect(origin: startOrigin, size: previewSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        alphaValue = 0

        let view = CornerPreviewView(frame: NSRect(origin: .zero, size: previewSize), icon: icon)
        view.onConfirm = { [weak self] in self?.onConfirm?() }
        contentView = view
    }

    /// Slides the panel in from just beyond the screen corner, as if it were
    /// emerging from off-screen, into its resting position near the corner.
    func playIntroAnimation() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrameOrigin(self.restingOrigin)
            self.animator().alphaValue = 1
        }
    }

    private static func restingOrigin(for corner: Corner, in screenFrame: NSRect, size: NSSize, margin: CGFloat) -> NSPoint {
        switch corner {
        case .topLeft:
            return NSPoint(x: screenFrame.minX + margin, y: screenFrame.maxY - margin - size.height)
        case .topRight:
            return NSPoint(x: screenFrame.maxX - margin - size.width, y: screenFrame.maxY - margin - size.height)
        case .bottomLeft:
            return NSPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)
        case .bottomRight:
            return NSPoint(x: screenFrame.maxX - margin - size.width, y: screenFrame.minY + margin)
        }
    }

    /// A starting position shifted diagonally beyond the physical corner,
    /// so the panel appears to fly in from off-screen rather than pop in place.
    private static func offscreenOrigin(for corner: Corner, restingOrigin: NSPoint, size: NSSize) -> NSPoint {
        let dx = size.width * 0.85
        let dy = size.height * 0.85
        switch corner {
        case .topLeft:
            return NSPoint(x: restingOrigin.x - dx, y: restingOrigin.y + dy)
        case .topRight:
            return NSPoint(x: restingOrigin.x + dx, y: restingOrigin.y + dy)
        case .bottomLeft:
            return NSPoint(x: restingOrigin.x - dx, y: restingOrigin.y - dy)
        case .bottomRight:
            return NSPoint(x: restingOrigin.x + dx, y: restingOrigin.y - dy)
        }
    }
}

private final class CornerPreviewView: NSView {
    var onConfirm: (() -> Void)?

    private let cornerRadius: CGFloat = 22
    private let shapeLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private var isHovering = false {
        didSet { updateFill() }
    }

    private let baseFill = NSColor.windowBackgroundColor.withAlphaComponent(0.98)
    private let hoverFill = NSColor.controlAccentColor.withAlphaComponent(0.16)

    init(frame: NSRect, icon: NSImage?) {
        super.init(frame: frame)

        wantsLayer = true

        shapeLayer.strokeColor = NSColor.separatorColor.cgColor
        shapeLayer.lineWidth = 1
        shapeLayer.shadowColor = NSColor.black.cgColor
        shapeLayer.shadowOpacity = 0.35
        shapeLayer.shadowRadius = 16
        shapeLayer.shadowOffset = NSSize(width: 0, height: -2)
        layer?.addSublayer(shapeLayer)
        updateFill()

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 144),
            iconView.heightAnchor.constraint(equalToConstant: 144),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let path = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        shapeLayer.path = path
        shapeLayer.shadowPath = path
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }
    override func mouseDown(with event: NSEvent) { onConfirm?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func updateFill() {
        shapeLayer.fillColor = (isHovering ? hoverFill.blended(withFraction: 0.9, of: baseFill) : baseFill)?.cgColor
    }
}
