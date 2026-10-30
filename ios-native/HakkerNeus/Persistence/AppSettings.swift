import CoreGraphics
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

    static let cornerButtonSideDidChange = Notification.Name("AppSettings.cornerButtonSideDidChange")

    /// The front page's corner button sits lower-left (for left hands) instead of lower-right.
    var cornerButtonOnLeft: Bool {
        get { defaults.bool(forKey: "cornerButtonOnLeft") }
        set {
            defaults.set(newValue, forKey: "cornerButtonOnLeft")
            NotificationCenter.default.post(name: Self.cornerButtonSideDidChange, object: nil)
        }
    }

    /// Comment text size and code wrapping; also sets `CommentTextStyle.current`.
    var commentTextStyle: CommentTextStyle {
        get {
            CommentTextStyle(
                wrapsLines: defaults.bool(forKey: "codeWrapsLines"),
                size: defaults.string(forKey: "codeSize").flatMap(CommentTextStyle.Size.init(rawValue:)) ?? .medium
            )
        }
        set {
            defaults.set(newValue.wrapsLines, forKey: "codeWrapsLines")
            defaults.set(newValue.size.rawValue, forKey: "codeSize")
            CommentTextStyle.current = newValue
        }
    }

    /// Open article links in Safari's Reader mode when the page supports it.
    var opensLinksInReaderMode: Bool {
        get { defaults.bool(forKey: "opensLinksInReaderMode") }
        set { defaults.set(newValue, forKey: "opensLinksInReaderMode") }
    }
}

/// Comment (and self-post) text: its size, and whether code blocks wrap or scroll sideways.
struct CommentTextStyle: Equatable {
    enum Size: String, CaseIterable {
        case small, medium, large

        var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            }
        }

        /// Body text point size before Dynamic Type scaling; medium is the original 16.
        var bodyPointSize: CGFloat {
            switch self {
            case .small: 14
            case .medium: 16
            case .large: 18
            }
        }

        /// Code is set 2pt smaller than the text around it (medium: the original 14).
        var codePointSize: CGFloat { bodyPointSize - 2 }
    }

    var wrapsLines = false
    var size = Size.medium

    /// Set from `AppSettings` at launch and when changed in Settings. Comment bodies are built
    /// each time a comment is shown, so changes apply to the next comments shown.
    nonisolated(unsafe) static var current = CommentTextStyle()
}
