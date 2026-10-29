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

    enum Font {
        /// Story titles: Helvetica Neue Light, 25pt on iPhone and 30pt on iPad.
        static func title(isPad: Bool) -> UIFont {
            helveticaNeue("HelveticaNeue-Light", size: isPad ? 30 : 25, weight: .light)
        }

        static func body(size: CGFloat = postAuthorFontSize) -> UIFont {
            helveticaNeue("HelveticaNeue", size: size, weight: .regular)
        }

        static func medium(size: CGFloat) -> UIFont {
            helveticaNeue("HelveticaNeue-Medium", size: size, weight: .medium)
        }

        static func bold(size: CGFloat) -> UIFont {
            helveticaNeue("HelveticaNeue-Bold", size: size, weight: .bold)
        }

        static func light(size: CGFloat) -> UIFont {
            helveticaNeue("HelveticaNeue-Light", size: size, weight: .light)
        }

        static func monospaced(size: CGFloat = 14) -> UIFont {
            UIFont(name: "Menlo-Regular", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)
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
