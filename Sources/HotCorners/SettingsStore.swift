import Foundation
import AppKit
import Combine

enum CardTheme: String, CaseIterable {
    case light
    case dark

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var appPaths: [Corner: String] = [:]
    @Published var launchAtLogin: Bool = false {
        didSet { LoginItem.setEnabled(launchAtLogin) }
    }
    @Published var cardTheme: CardTheme = .light {
        didSet { defaults.set(cardTheme.rawValue, forKey: cardThemeKey) }
    }
    @Published var cardScale: Double = 1.0 {
        didSet { defaults.set(cardScale, forKey: cardScaleKey) }
    }

    private let defaults = UserDefaults.standard
    private let keyPrefix = "corner.app."
    private let cardThemeKey = "cardTheme"
    private let cardScaleKey = "cardScale"

    private init() {
        for corner in Corner.allCases {
            if let path = defaults.string(forKey: keyPrefix + corner.rawValue) {
                appPaths[corner] = path
            }
        }
        launchAtLogin = LoginItem.isEnabled
        if let raw = defaults.string(forKey: cardThemeKey), let theme = CardTheme(rawValue: raw) {
            cardTheme = theme
        }
        if defaults.object(forKey: cardScaleKey) != nil {
            cardScale = defaults.double(forKey: cardScaleKey)
        }
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
