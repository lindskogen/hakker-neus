import Testing
@testable import HakkerNeus

struct PaletteTests {
    /// Expected values come from `d3-scale-chromatic@2`'s `interpolateOranges`.
    @Test(arguments: [
        (0.0, Palette.RGB(r: 255, g: 245, b: 235)),
        (0.3, Palette.RGB(r: 253, g: 194, b: 140)),
        (0.65, Palette.RGB(r: 235, g: 99, b: 17)),
        (0.72, Palette.RGB(r: 221, g: 81, b: 7)),
        (0.9, Palette.RGB(r: 159, g: 51, b: 3)),
        (1.0, Palette.RGB(r: 127, g: 39, b: 4)),
        (1.07, Palette.RGB(r: 127, g: 39, b: 4)),
    ])
    func orangesMatchesD3(t: Double, expected: Palette.RGB) {
        #expect(Palette.orangesRGB(t) == expected)
    }

    @Test func storyBackgroundGetsDarkerDownTheList() {
        #expect(Palette.orangesRGB(Double(25) / 50 * 0.35 + 0.65) == Palette.RGB(r: 187, g: 61, b: 2))
        #expect(Palette.orangesRGB(Double(49) / 50 * 0.35 + 0.65) == Palette.RGB(r: 129, g: 40, b: 4))
    }

    @Test func topLevelCommentsHaveNoDepthColor() {
        #expect(Palette.commentDepth(0) == .clear)
        #expect(Palette.commentDepth(1) == Palette.commentDepth(11))
    }
}
