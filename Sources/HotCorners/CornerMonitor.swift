import AppKit

final class CornerMonitor {
    private var timer: Timer?
    private let threshold: CGFloat = 4
    private let pollInterval: TimeInterval = 0.08

    private var previewPanel: CornerPreviewPanel?
    private var previewCorner: Corner?
    /// Corner that was just confirmed; suppressed until the pointer leaves
    /// the hot zone so it doesn't instantly reopen under the cursor.
    private var suppressedCorner: Corner?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hidePreview()
    }

    private func tick() {
        let point = NSEvent.mouseLocation
        guard let screen = screenContaining(point) else {
            hidePreview()
            suppressedCorner = nil
            return
        }

        if let panel = previewPanel {
            if panel.hoverZone(in: screen.frame).insetBy(dx: -1, dy: -1).contains(point) {
                return
            }
            hidePreview()
        }

        let corner = cornerHit(point: point, in: screen.frame)

        guard let corner else {
            suppressedCorner = nil
            return
        }

        if corner == suppressedCorner { return }
        suppressedCorner = nil

        guard SettingsStore.shared.appPaths[corner] != nil else { return }
        showPreview(for: corner, in: screen)
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

    private func showPreview(for corner: Corner, in screen: NSScreen) {
        guard let path = SettingsStore.shared.appPaths[corner] else { return }
        let icon = SettingsStore.shared.appIcon(for: corner)

        let panel = CornerPreviewPanel(corner: corner, icon: icon, screenFrame: screen.frame)
        panel.onConfirm = { [weak self] in
            self?.launch(path: path)
            self?.suppressedCorner = corner
            self?.hidePreview()
        }
        panel.orderFrontRegardless()
        panel.playIntroAnimation()

        previewPanel = panel
        previewCorner = corner
    }

    private func hidePreview() {
        guard let panel = previewPanel else { return }
        previewPanel = nil
        previewCorner = nil
        panel.playOutroAnimation {
            panel.orderOut(nil)
        }
    }

    private func launch(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("HotCorners: failed to launch \(path): \(error)")
            }
        }
    }
}
