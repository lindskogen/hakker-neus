import UIKit

/// Port of `src/common/vars.ts`.
enum Theme {
    static let padding: CGFloat = 10
    static let postAuthorFontSize: CGFloat = 16

    enum Color {
        static let backgroundDark = UIColor(rgb: 0x1B1D21)
        static let backgroundRed = UIColor(rgb: 0xCE5B4C)
        static let backgroundOrange = Palette.oranges(0.65)
    }

    /// The RN app's fonts, scaled with Dynamic Type. Each font follows the system text style
    /// closest to its role, so at the default text size it is exactly the RN app's size.
    /// Labels using these need `adjustsFontForContentSizeCategory` to follow changes live.
    enum Font {
        /// Story titles: Helvetica Neue Light, 25pt on iPhone and 30pt on iPad.
        static func title(isPad: Bool, traits: UITraitCollection? = nil) -> UIFont {
            scaled(helveticaNeue("HelveticaNeue-Light", size: isPad ? 30 : 25, weight: .light), .title1, traits)
        }

        static func body(size: CGFloat = postAuthorFontSize, style: UIFont.TextStyle = .body, maximum: CGFloat? = nil, traits: UITraitCollection? = nil) -> UIFont {
            scaled(helveticaNeue("HelveticaNeue", size: size, weight: .regular), style, traits, maximum: maximum)
        }

        static func medium(size: CGFloat, style: UIFont.TextStyle = .footnote, traits: UITraitCollection? = nil) -> UIFont {
            scaled(helveticaNeue("HelveticaNeue-Medium", size: size, weight: .medium), style, traits)
        }

        static func bold(size: CGFloat, style: UIFont.TextStyle = .caption2, maximum: CGFloat? = nil, traits: UITraitCollection? = nil) -> UIFont {
            scaled(helveticaNeue("HelveticaNeue-Bold", size: size, weight: .bold), style, traits, maximum: maximum)
        }

        static func light(size: CGFloat, style: UIFont.TextStyle = .title2, traits: UITraitCollection? = nil) -> UIFont {
            scaled(helveticaNeue("HelveticaNeue-Light", size: size, weight: .light), style, traits)
        }

        static func monospaced(size: CGFloat = 14, traits: UITraitCollection? = nil) -> UIFont {
            let font = UIFont(name: "Menlo-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
            return scaled(font, .body, traits)
        }

        private static func scaled(_ font: UIFont, _ style: UIFont.TextStyle, _ traits: UITraitCollection?, maximum: CGFloat? = nil) -> UIFont {
            let metrics = UIFontMetrics(forTextStyle: style)
            if let maximum {
                return metrics.scaledFont(for: font, maximumPointSize: maximum, compatibleWith: traits)
            }
            return metrics.scaledFont(for: font, compatibleWith: traits)
        }

        private static func helveticaNeue(_ name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
            UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        }
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
