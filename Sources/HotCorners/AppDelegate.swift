import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let monitor = CornerMonitor()
    private var updateItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.dashed.inset.filled", accessibilityDescription: "Hot Corners")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        updateItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hot Corners", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu

        monitor.start()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Hot Corners"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Updates

    @objc private func checkForUpdates() {
        setUpdateItem(title: "Checking…", enabled: false)

        Updater.check { [weak self] result in
            guard let self else { return }
            self.setUpdateItem(title: "Check for Updates…", enabled: true)

            switch result {
            case .success(.upToDate(let build)):
                self.showAlert(
                    title: "You're up to date",
                    message: "Hot Corners build \(build) is the latest version.",
                    style: .informational
                )
            case .success(.noReleases):
                self.showAlert(
                    title: "No releases yet",
                    message: "This repository has no published releases to update from.",
                    style: .informational
                )
            case .success(.available(let release)):
                self.offerUpdate(release)
            case .failure(let error):
                self.showAlert(
                    title: "Couldn't check for updates",
                    message: error.localizedDescription,
                    style: .warning
                )
            }
        }
    }

    private func offerUpdate(_ release: Updater.Release) {
        let current = Updater.localBuild.map(String.init) ?? "unknown"
        var text = "\(release.title)\n\nYou have build \(current), build \(release.build) is available."
        if !release.notes.isEmpty {
            text += "\n\n\(release.notes)"
        }

        let alert = NSAlert()
        alert.messageText = "Update available"
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update and Restart")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "View on GitHub")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            setUpdateItem(title: "Updating…", enabled: false)
            Updater.install(release) { [weak self] error in
                guard let self, let error else { return }  // on success the app relaunches itself
                self.setUpdateItem(title: "Check for Updates…", enabled: true)
                self.showAlert(title: "Update failed", message: error.localizedDescription, style: .warning)
            }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private func setUpdateItem(title: String, enabled: Bool) {
        updateItem.title = title
        updateItem.action = enabled ? #selector(checkForUpdates) : nil
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
