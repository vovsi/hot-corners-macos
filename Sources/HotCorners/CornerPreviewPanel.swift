import AppKit

/// A small floating card that appears near the screen corner the user is
/// hovering, showing which app will launch. Clicking it confirms the launch.
final class CornerPreviewPanel: NSPanel {
    var onConfirm: (() -> Void)?

    /// Base card size at `cardScale == 1.0`; the panel and its icon scale
    /// uniformly from this baseline.
    private static let baseSize: CGFloat = 96
    private let previewSize: NSSize
    /// Fraction of the card kept on-screen at rest; the remainder hangs past
    /// the physical screen edge, as if the card is emerging from behind the
    /// monitor's bezel.
    private let visibleFraction: CGFloat = 0.8
    private let corner: Corner
    private let restingOrigin: NSPoint
    private let offscreenOrigin: NSPoint

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
        let scale = CGFloat(SettingsStore.shared.cardScale)
        let previewSize = NSSize(width: CornerPreviewPanel.baseSize * scale, height: CornerPreviewPanel.baseSize * scale)
        self.previewSize = previewSize
        let restingOrigin = CornerPreviewPanel.restingOrigin(for: corner, in: screenFrame, size: previewSize, visibleFraction: visibleFraction)
        let startOrigin = CornerPreviewPanel.offscreenOrigin(for: corner, restingOrigin: restingOrigin, size: previewSize)
        self.restingOrigin = restingOrigin
        self.offscreenOrigin = startOrigin

        super.init(
            contentRect: NSRect(origin: startOrigin, size: previewSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        alphaValue = 1

        let view = CornerPreviewView(frame: NSRect(origin: .zero, size: previewSize), icon: icon, scale: scale, corner: corner)
        view.onConfirm = { [weak self] in self?.onConfirm?() }
        contentView = view
    }

    /// Slides the panel in from just beyond the screen corner, as if it were
    /// emerging from off-screen, into its resting position near the corner.
    func playIntroAnimation() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(NSRect(origin: self.restingOrigin, size: self.frame.size), display: true)
        }
    }

    /// Slides the panel back off-screen, mirroring the intro animation, then
    /// invokes `completion` once it's fully retreated.
    func playOutroAnimation(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(NSRect(origin: self.offscreenOrigin, size: self.frame.size), display: true)
        }, completionHandler: completion)
    }

    private static func restingOrigin(for corner: Corner, in screenFrame: NSRect, size: NSSize, visibleFraction: CGFloat) -> NSPoint {
        let hiddenWidth = size.width * (1 - visibleFraction)
        let hiddenHeight = size.height * (1 - visibleFraction)
        switch corner {
        case .topLeft:
            return NSPoint(x: screenFrame.minX - hiddenWidth, y: screenFrame.maxY - size.height + hiddenHeight)
        case .topRight:
            return NSPoint(x: screenFrame.maxX - size.width + hiddenWidth, y: screenFrame.maxY - size.height + hiddenHeight)
        case .bottomLeft:
            return NSPoint(x: screenFrame.minX - hiddenWidth, y: screenFrame.minY - hiddenHeight)
        case .bottomRight:
            return NSPoint(x: screenFrame.maxX - size.width + hiddenWidth, y: screenFrame.minY - hiddenHeight)
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

    private let cornerRadius: CGFloat
    /// Radius of the one card corner that sits fully on-screen (the rest
    /// hang past the physical screen edge behind the monitor bezel), matched
    /// to `iconClip`'s corner radius so the card's only visible rounding
    /// reads consistently with the icon it contains.
    private let visibleCornerRadius: CGFloat
    private let corner: Corner
    private let shapeLayer = CAShapeLayer()
    private let iconView = NSImageView()

    /// `NSColor.windowBackgroundColor` is a system "material" color whose
    /// `.cgColor` bridging isn't guaranteed fully opaque (it's meant to be
    /// backed by a blur/vibrancy layer). Since this card has no such layer,
    /// desktop content bled through it. Plain `NSColor(white:alpha:)` values
    /// are true flat RGBA and always render 100% opaque.
    private var baseFill: NSColor {
        SettingsStore.shared.cardTheme == .dark
            ? NSColor(white: 0.0, alpha: 1)
            : NSColor(white: 0.98, alpha: 1)
    }

    init(frame: NSRect, icon: NSImage?, scale: CGFloat, corner: Corner) {
        self.cornerRadius = 10 * scale
        self.visibleCornerRadius = 27.92 * scale
        self.corner = corner
        super.init(frame: frame)

        wantsLayer = true

        shapeLayer.strokeColor = NSColor.separatorColor.cgColor
        shapeLayer.lineWidth = 1
        shapeLayer.shadowOpacity = 0
        layer?.addSublayer(shapeLayer)
        updateFill()

        // macOS app icons ship with a faint drop shadow baked into the
        // artwork's transparent padding, meant to sit on top of the Dock's
        // blurred background. On our flat card it reads as a grey smudge, so
        // the icon is clipped to a slightly tighter rounded rect and
        // overscaled to crop that shadow ring away.
        let iconClip = NSView()
        iconClip.wantsLayer = true
        iconClip.layer?.cornerRadius = 13 * scale
        iconClip.layer?.masksToBounds = true
        iconClip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconClip)

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconClip.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconClip.widthAnchor.constraint(equalToConstant: 64 * scale),
            iconClip.heightAnchor.constraint(equalToConstant: 64 * scale),
            iconClip.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconClip.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 70 * scale),
            iconView.heightAnchor.constraint(equalToConstant: 70 * scale),
            iconView.centerXAnchor.constraint(equalTo: iconClip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconClip.centerYAnchor),
        ])

    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        shapeLayer.frame = bounds
        shapeLayer.path = cardPath(in: bounds)
    }

    override func mouseDown(with event: NSEvent) { onConfirm?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func updateFill() {
        shapeLayer.fillColor = baseFill.cgColor
    }

    /// Builds the card outline with per-corner radii: the one corner that
    /// sits fully on-screen (opposite the physical screen corner that
    /// triggered the panel) uses `visibleCornerRadius`; the other three —
    /// which hang past the screen edge and are never actually seen — keep
    /// `cornerRadius`.
    private func cardPath(in rect: CGRect) -> CGPath {
        var topLeft = cornerRadius
        var topRight = cornerRadius
        var bottomLeft = cornerRadius
        var bottomRight = cornerRadius
        switch corner {
        case .topLeft: bottomRight = visibleCornerRadius
        case .topRight: bottomLeft = visibleCornerRadius
        case .bottomLeft: topRight = visibleCornerRadius
        case .bottomRight: topLeft = visibleCornerRadius
        }

        let path = CGMutablePath()
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        path.move(to: CGPoint(x: minX + bottomLeft, y: minY))
        path.addLine(to: CGPoint(x: maxX - bottomRight, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + bottomRight), radius: bottomRight)
        path.addLine(to: CGPoint(x: maxX, y: maxY - topRight))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - topRight, y: maxY), radius: topRight)
        path.addLine(to: CGPoint(x: minX + topLeft, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - topLeft), radius: topLeft)
        path.addLine(to: CGPoint(x: minX, y: minY + bottomLeft))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + bottomLeft, y: minY), radius: bottomLeft)
        path.closeSubpath()
        return path
    }
}
