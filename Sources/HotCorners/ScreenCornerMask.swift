import AppKit

/// Paints opaque black wedges over the two bottom corners of every screen so
/// the display reads as rounded at the bottom the same way it already is at
/// the top. Purely cosmetic: the overlays never take mouse events, so the
/// bottom hot corners keep working underneath them.
final class ScreenCornerMask {
    private var windows: [NSWindow] = []
    private var enabled = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        rebuild()
    }

    @objc private func screenParametersChanged() {
        rebuild()
    }

    private func rebuild() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        guard enabled else { return }

        for screen in NSScreen.screens {
            let radius = ScreenCornerMask.topCornerRadius(of: screen)
            guard radius > 0.5 else { continue }   // square display: nothing to match
            for corner in [Corner.bottomLeft, Corner.bottomRight] {
                windows.append(makeWindow(corner: corner, radius: radius, screen: screen))
            }
        }
    }

    private func makeWindow(corner: Corner, radius: CGFloat, screen: NSScreen) -> NSWindow {
        let frame = screen.frame
        let origin = corner == .bottomLeft
            ? NSPoint(x: frame.minX, y: frame.minY)
            : NSPoint(x: frame.maxX - radius, y: frame.minY)

        let window = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: radius, height: radius)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = CornerWedgeView(
            frame: NSRect(origin: .zero, size: NSSize(width: radius, height: radius)),
            corner: corner
        )
        window.orderFrontRegardless()
        return window
    }

    // MARK: - Display corner radius

    private typealias CornerRadiiFn = @convention(c) (
        UInt32,
        UnsafeMutablePointer<CGFloat>,
        UnsafeMutablePointer<CGFloat>,
        UnsafeMutablePointer<CGFloat>,
        UnsafeMutablePointer<CGFloat>
    ) -> Int32

    private static let cornerRadiiFn: CornerRadiiFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "SLSDisplayGetCornerRadii") else { return nil }
        return unsafeBitCast(symbol, to: CornerRadiiFn.self)
    }()

    /// The radius macOS itself rounds this display's corners with. There's no
    /// public API for it, so this goes through the private
    /// `SLSDisplayGetCornerRadii`, which reports one radius per corner; on a
    /// notched MacBook only the top two are non-zero, which is exactly the
    /// radius we want to mirror at the bottom. Falls back to the notch-era
    /// default only when the private call is unavailable.
    static func topCornerRadius(of screen: NSScreen) -> CGFloat {
        let notchFallback: CGFloat = screen.safeAreaInsets.top > 0 ? 20 : 0
        guard let displayID = screen.displayID, let fn = cornerRadiiFn else { return notchFallback }

        var radii = [CGFloat](repeating: 0, count: 4)
        let succeeded = radii.withUnsafeMutableBufferPointer { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            return fn(displayID, base, base + 1, base + 2, base + 3) == 0
        }
        guard succeeded else { return notchFallback }
        return radii.max() ?? 0
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// A square the size of the corner radius, filled black everywhere except the
/// quarter disc that makes up the rounded corner itself.
private final class CornerWedgeView: NSView {
    private let corner: Corner

    init(frame: NSRect, corner: Corner) {
        self.corner = corner
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.width
        // The circle sits inside the screen, tangent to both edges; the wedge
        // is everything between the physical corner and that circle.
        let center = corner == .bottomLeft
            ? NSPoint(x: radius, y: radius)
            : NSPoint(x: 0, y: radius)
        let cornerPoint = corner == .bottomLeft
            ? NSPoint(x: 0, y: 0)
            : NSPoint(x: radius, y: 0)

        let path = NSBezierPath()
        path.move(to: cornerPoint)
        path.line(to: NSPoint(x: cornerPoint.x, y: radius))
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: corner == .bottomLeft ? 180 : 0,
            endAngle: 270,
            clockwise: corner != .bottomLeft
        )
        path.line(to: cornerPoint)
        path.close()

        NSColor.black.setFill()
        path.fill()
    }
}
