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

    @Test("a light target never matches a dark-only candidate when a light one exists")
    func lightnessClassIsRespected() {
        let target = LabColor(red: 0.95, green: 0.9, blue: 0.92) // pale pink
        let palette = [
            MardColor(code: "DARK", hex: "1A0A0D"), // near-black, would win on raw distance to a saturated version
            MardColor(code: "LIGHT", hex: "FFE8ED"), // pale pink, correct lightness class
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "LIGHT")
    }

    @Test("a dark target never matches a light-only candidate when a dark one exists")
    func darkTargetPrefersDarkCandidate() {
        let target = LabColor(red: 0.08, green: 0.05, blue: 0.06)
        let palette = [
            MardColor(code: "LIGHT", hex: "FFEEF0"),
            MardColor(code: "DARK", hex: "200E10"),
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "DARK")
    }

    @Test("a high-saturation target prefers a high-saturation candidate over a closer low-saturation one")
    func saturationClassIsRespected() {
        // Target and both candidates share the same dark lightness class, isolating the
        // saturation-class filter: MUTED is Lab-closer to the target but low-saturation, VIVID
        // is farther but high-saturation like the target and should win.
        let target = LabColor(red: 0.7, green: 0.098, blue: 0.098) // #B31919
        let palette = [
            MardColor(code: "MUTED", hex: "7D2828"), // low-saturation, closer in raw distance
            MardColor(code: "VIVID", hex: "5A0005"), // high-saturation, correct saturation class
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "VIVID")
    }

    @Test("a near-gray target matches a neutral candidate rather than a chromatic one")
    func neutralTargetPrefersNeutralCandidate() {
        let target = LabColor(red: 0.55, green: 0.55, blue: 0.56) // near-gray
        let palette = [
            MardColor(code: "CHROMATIC", hex: "8888D0"), // slightly bluish, chromatic
            MardColor(code: "NEUTRAL", hex: "8A8A8C"), // true neutral gray
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "NEUTRAL")
    }

    @Test("a saturated target never matches its near-complementary hue when a same-hue-family candidate exists")
    func complementaryHueIsExcluded() {
        // Target, ORANGE, and CYAN share the same dark/high-saturation class, isolating the hue
        // filter: ORANGE is Lab-closer (hue distance ~150°, near-complementary) but excluded;
        // CYAN is farther but same hue family (~60° away) and should be preferred.
        let target = LabColor(red: 0.1, green: 0.3, blue: 0.75) // #1A4DBF-ish saturated blue
        let palette = [
            MardColor(code: "ORANGE", hex: "AB6351"),
            MardColor(code: "CYAN", hex: "005A3F"),
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "CYAN")
    }

    @Test("forcedLightness overrides the target's own lightness class")
    func forcedLightnessOverridesTarget() {
        // Target is a light pastel, but forcing .dark should select the dark candidate anyway
        // (used for contour pixels, which must render as dark beads).
        let target = LabColor(red: 0.9, green: 0.85, blue: 0.88)
        let palette = [
            MardColor(code: "LIGHT", hex: "FFE8ED"),
            MardColor(code: "DARK", hex: "2A1A1D"),
        ]
        let match = ColorMatcher.nearest(to: target, in: palette, forcedLightness: .dark)
        #expect(match.code == "DARK")
    }

    @Test("rankedCandidates returns every rule-compliant candidate sorted by distance, nearest first")
    func rankedCandidatesSortedByDistance() {
        let target = LabColor(red: 0.9, green: 0.05, blue: 0.05)
        let palette = [
            MardColor(code: "FAR", hex: "D02020"),
            MardColor(code: "NEAR", hex: "F00000"),
        ]
        let ranked = ColorMatcher.rankedCandidates(for: target, in: palette)
        #expect(ranked.map(\.code) == ["NEAR", "FAR"])
    }

    @Test("nearest never crashes when the palette has no candidates matching the target's exact class")
    func fallsBackWhenNoExactClassMatch() {
        // Every candidate is dark; a light target must still resolve to something rather than
        // crashing on an empty filtered array.
        let target = LabColor(red: 0.95, green: 0.9, blue: 0.92)
        let palette = [
            MardColor(code: "ONLY_DARK", hex: "150A0C"),
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "ONLY_DARK")
    }
}
