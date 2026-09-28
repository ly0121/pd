import Testing
@testable import BeadCore

@Suite("ColorMatcher")
struct ColorMatcherTests {
    @Test("pure black RGB matches MARD H7 exactly")
    func pureBlackMatchesH7() {
        let black = LabColor(red: 0, green: 0, blue: 0)
        let match = ColorMatcher.nearest(to: black, in: MardPalette.standard221)
        #expect(match.code == "H7")
    }

    @Test("pure white RGB matches a near-white MARD color")
    func pureWhiteMatchesNearWhite() {
        let white = LabColor(red: 1, green: 1, blue: 1)
        let match = ColorMatcher.nearest(to: white, in: MardPalette.standard221)
        // H1/H2 are the two near-white MARD colors in the palette.
        #expect(match.code == "H1" || match.code == "H2")
    }

    @Test("distance to self is zero")
    func distanceToSelfIsZero() {
        let color = LabColor(red: 0.5, green: 0.3, blue: 0.8)
        #expect(color.distance(to: color) == 0.0)
    }

    @Test("nearest color is deterministic for a fixed palette order")
    func deterministicForTiedDistances() {
        let palette = [
            MardColor(code: "X1", hex: "808080"),
            MardColor(code: "X2", hex: "808080"),
        ]
        let target = LabColor(red: 0.5, green: 0.5, blue: 0.5)
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "X1")
    }
}
