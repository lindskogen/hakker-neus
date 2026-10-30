import Foundation

/// User preferences, in UserDefaults.
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Open article links in Safari's Reader mode when the page supports it.
    var opensLinksInReaderMode: Bool {
        get { defaults.bool(forKey: "opensLinksInReaderMode") }
        set { defaults.set(newValue, forKey: "opensLinksInReaderMode") }
    }
}
