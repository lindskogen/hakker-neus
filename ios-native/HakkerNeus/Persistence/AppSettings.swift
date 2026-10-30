import Foundation

/// User preferences, in UserDefaults.
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static let colorThemeDidChange = Notification.Name("AppSettings.colorThemeDidChange")

    /// The front page's colours; also sets `ColorTheme.current`.
    var colorTheme: ColorTheme {
        get { defaults.string(forKey: "colorTheme").flatMap(ColorTheme.init(rawValue:)) ?? .orange }
        set {
            defaults.set(newValue.rawValue, forKey: "colorTheme")
            ColorTheme.current = newValue
            NotificationCenter.default.post(name: Self.colorThemeDidChange, object: nil)
        }
    }

    /// Open article links in Safari's Reader mode when the page supports it.
    var opensLinksInReaderMode: Bool {
        get { defaults.bool(forKey: "opensLinksInReaderMode") }
        set { defaults.set(newValue, forKey: "opensLinksInReaderMode") }
    }
}
