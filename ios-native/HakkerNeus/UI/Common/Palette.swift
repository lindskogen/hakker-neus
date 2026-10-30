import UIKit

/// The colour of the front page and the accents that go with it. Orange is the original;
/// blue and green use d3's Blues and Greens the same way. The saved list stays red in all.
enum ColorTheme: String, CaseIterable {
    case orange
    case blue
    case green

    /// Set from `AppSettings` at launch and when changed in Settings.
    nonisolated(unsafe) static var current: ColorTheme = .orange

    /// The matching home screen icon (an alternate icon in the asset catalog); nil is the main one.
    var alternateIconName: String? {
        switch self {
        case .orange: nil
        case .blue: "AppIcon-Blue"
        case .green: "AppIcon-Green"
        }
    }

    var title: String {
        switch self {
        case .orange: "Orange"
        case .blue: "Blue"
        case .green: "Green"
        }
    }

    fileprivate var stops: [(Double, Double, Double)] {
        switch self {
        case .orange: Palette.orangesStops
        case .blue: Palette.bluesStops
        case .green: Palette.greensStops
        }
    }
}

/// Ports of the `d3-scale-chromatic` schemes the app uses.
enum Palette {
    /// 8-bit RGB triple, kept separate from UIColor so it can be unit tested exactly.
    struct RGB: Equatable {
        var r: UInt8
        var g: UInt8
        var b: UInt8

        var uiColor: UIColor {
            UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }

    /// `d3.interpolateOranges(t)`: a uniform B-spline through the 9-class Oranges scheme.
    static func oranges(_ t: Double) -> UIColor {
        orangesRGB(t).uiColor
    }

    static func orangesRGB(_ t: Double) -> RGB {
        interpolate(orangesStops, t)
    }

    /// `d3.interpolateReds(t)`, for the saved stories list.
    static func redsRGB(_ t: Double) -> RGB {
        interpolate(redsStops, t)
    }

    /// The current theme's ramp at `t`, like `d3.interpolateOranges(t)` for orange.
    static func themeRGB(_ t: Double, theme: ColorTheme = .current) -> RGB {
        interpolate(theme.stops, t)
    }

    /// Background for row `index` of the story list (`getBackgroundColor` in `NewsList.tsx`).
    static func storyBackground(at index: Int, theme: ColorTheme = .current) -> UIColor {
        themeRGB(rowPosition(index), theme: theme).uiColor
    }

    /// The colour of the comments header and other accents: the first row's colour.
    static func accent(theme: ColorTheme = .current) -> UIColor {
        themeRGB(0.65, theme: theme).uiColor
    }

    /// Behind a row at the upvote stage of a swipe: blue, or orange when the rows are blue.
    static var upvoteStage: UIColor {
        UIColor(rgb: tableau10[ColorTheme.current == .blue ? 1 : 0])
    }

    /// Background for row `index` of the saved list: the same ramp in red, so it's clear which list you're on.
    static func savedStoryBackground(at index: Int) -> UIColor {
        redsRGB(rowPosition(index)).uiColor
    }

    private static func rowPosition(_ index: Int) -> Double {
        Double(index) / 50 * 0.35 + 0.65
    }

    private static func interpolate(_ stops: [(Double, Double, Double)], _ t: Double) -> RGB {
        RGB(
            r: channel(basisSpline(stops.map(\.0), t)),
            g: channel(basisSpline(stops.map(\.1), t)),
            b: channel(basisSpline(stops.map(\.2), t))
        )
    }

    /// `d3.schemeTableau10[depth]`, used for the left border of nested comments.
    /// Depth 0 has no border. The RN app showed no border past depth 9; this wraps instead.
    static func commentDepth(_ depth: Int) -> UIColor {
        depth == 0 ? .clear : UIColor(rgb: tableau10[depth % tableau10.count])
    }

    static let tableau10: [UInt32] = [
        0x4E79A7, 0xF28E2C, 0xE15759, 0x76B7B2, 0x59A14F,
        0xEDC949, 0xAF7AA1, 0xFF9DA7, 0x9C755F, 0xBAB0AB,
    ]

    fileprivate static let bluesStops = stops([
        0xF7FBFF, 0xDEEBF7, 0xC6DBEF, 0x9ECAE1, 0x6BAED6,
        0x4292C6, 0x2171B5, 0x08519C, 0x08306B,
    ])

    fileprivate static let greensStops = stops([
        0xF7FCF5, 0xE5F5E0, 0xC7E9C0, 0xA1D99B, 0x74C476,
        0x41AB5D, 0x238B45, 0x006D2C, 0x00441B,
    ])

    fileprivate static let orangesStops = stops([
        0xFFF5EB, 0xFEE6CE, 0xFDD0A2, 0xFDAE6B, 0xFD8D3C,
        0xF16913, 0xD94801, 0xA63603, 0x7F2704,
    ])

    private static let redsStops = stops([
        0xFFF5F0, 0xFEE0D2, 0xFCBBA1, 0xFC9272, 0xFB6A4A,
        0xEF3B2C, 0xCB181D, 0xA50F15, 0x67000D,
    ])

    private static func stops(_ colors: [UInt32]) -> [(Double, Double, Double)] {
        colors.map { (Double(($0 >> 16) & 0xFF), Double(($0 >> 8) & 0xFF), Double($0 & 0xFF)) }
    }

    /// Same algorithm as `d3-interpolate`'s `basis`.
    private static func basisSpline(_ values: [Double], _ t: Double) -> Double {
        let n = values.count - 1
        let t = min(max(t, 0), 1)
        let i = t >= 1 ? n - 1 : Int((t * Double(n)).rounded(.down))
        let v1 = values[i]
        let v2 = values[i + 1]
        let v0 = i > 0 ? values[i - 1] : 2 * v1 - v2
        let v3 = i < n - 1 ? values[i + 2] : 2 * v2 - v1

        let t1 = (t - Double(i) / Double(n)) * Double(n)
        let t2 = t1 * t1
        let t3 = t2 * t1
        return ((1 - 3 * t1 + 3 * t2 - t3) * v0
            + (4 - 6 * t2 + 3 * t3) * v1
            + (1 + 3 * t1 + 3 * t2 - 3 * t3) * v2
            + t3 * v3) / 6
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(min(max(value.rounded(), 0), 255))
    }
}
