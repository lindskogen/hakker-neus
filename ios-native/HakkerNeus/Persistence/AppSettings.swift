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

    /// How code blocks in comments look; also sets `CodeBlockStyle.current`.
    var codeBlockStyle: CodeBlockStyle {
        get {
            CodeBlockStyle(
                wrapsLines: defaults.bool(forKey: "codeWrapsLines"),
                size: defaults.string(forKey: "codeSize").flatMap(CodeBlockStyle.Size.init(rawValue:)) ?? .medium
            )
        }
        set {
            defaults.set(newValue.wrapsLines, forKey: "codeWrapsLines")
            defaults.set(newValue.size.rawValue, forKey: "codeSize")
            CodeBlockStyle.current = newValue
        }
    }

    /// Open article links in Safari's Reader mode when the page supports it.
    var opensLinksInReaderMode: Bool {
        get { defaults.bool(forKey: "opensLinksInReaderMode") }
        set { defaults.set(newValue, forKey: "opensLinksInReaderMode") }
    }
}

/// Code blocks in comments: unwrapped (scrolling sideways) or wrapped, and their text size.
struct CodeBlockStyle: Equatable {
    enum Size: String, CaseIterable {
        case small, medium, large

        var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            }
        }

        /// Point size before Dynamic Type scaling; medium is the original 14.
        var pointSize: CGFloat {
            switch self {
            case .small: 12
            case .medium: 14
            case .large: 16
            }
        }
    }

    var wrapsLines = false
    var size = Size.medium

    /// Set from `AppSettings` at launch and when changed in Settings. Code blocks are built
    /// each time a comment is shown, so changes apply to the next comments shown.
    nonisolated(unsafe) static var current = CodeBlockStyle()
}
