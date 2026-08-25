import Foundation
import AppKit
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var appPaths: [Corner: String] = [:]
    @Published var launchAtLogin: Bool = false {
        didSet { LoginItem.setEnabled(launchAtLogin) }
    }

    private let defaults = UserDefaults.standard
    private let keyPrefix = "corner.app."

    private init() {
        for corner in Corner.allCases {
            if let path = defaults.string(forKey: keyPrefix + corner.rawValue) {
                appPaths[corner] = path
            }
        }
        launchAtLogin = LoginItem.isEnabled
    }

    func setApp(_ path: String?, for corner: Corner) {
        appPaths[corner] = path
        let key = keyPrefix + corner.rawValue
        if let path {
            defaults.set(path, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func appName(for corner: Corner) -> String? {
        guard let path = appPaths[corner] else { return nil }
        return FileManager.default.displayName(atPath: path)
    }

    func appIcon(for corner: Corner) -> NSImage? {
        guard let path = appPaths[corner] else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
