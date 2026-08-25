import AppKit

final class CornerMonitor {
    private var timer: Timer?
    private var activeCorner: Corner?
    private let threshold: CGFloat = 4
    private let pollInterval: TimeInterval = 0.08
    private var lastFireDate: Date = .distantPast
    private let refireCooldown: TimeInterval = 1.0

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let point = NSEvent.mouseLocation
        guard let screen = screenContaining(point) else {
            activeCorner = nil
            return
        }

        let corner = cornerHit(point: point, in: screen.frame)

        if let corner {
            if activeCorner != corner {
                activeCorner = corner
                fire(corner)
            }
        } else {
            activeCorner = nil
        }
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    private func cornerHit(point: NSPoint, in frame: NSRect) -> Corner? {
        let nearMinX = point.x - frame.minX <= threshold
        let nearMaxX = frame.maxX - point.x <= threshold
        let nearMinY = point.y - frame.minY <= threshold
        let nearMaxY = frame.maxY - point.y <= threshold

        if nearMinX && nearMinY { return .bottomLeft }
        if nearMaxX && nearMinY { return .bottomRight }
        if nearMinX && nearMaxY { return .topLeft }
        if nearMaxX && nearMaxY { return .topRight }
        return nil
    }

    private func fire(_ corner: Corner) {
        let now = Date()
        guard now.timeIntervalSince(lastFireDate) >= refireCooldown else { return }
        guard let path = SettingsStore.shared.appPaths[corner] else { return }
        lastFireDate = now
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("HotCorners: failed to launch \(path): \(error)")
            }
        }
    }
}
