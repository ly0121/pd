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

    @Test("neighboring grays do not jump at the HSL midpoint")
    func neighboringGraysPreserveTone() {
        let matches = [127, 128].map { value in
            let channel = Double(value) / 255
            return ColorMatcher.nearest(
                to: LabColor(red: channel, green: channel, blue: channel), in: MardPalette.standard221
            )
        }
        #expect(matches.map(\.code) == ["H4", "H4"])
    }

    @Test("unforced matching and ranking use continuous Lab distance within the selected palette")
    func matchingUsesAllAllowedCandidates() {
        for palette in [MardPalette.standard221, MardPalette.allColors] {
            for channel in [0.1, 0.3, 0.49, 0.5, 0.51, 0.7, 0.9] {
                for target in [
                    LabColor(red: channel, green: channel, blue: channel),
                    LabColor(red: 0.5, green: channel, blue: 0.3)
                ] {
                    let expected = palette.min { target.distance(to: $0.lab) < target.distance(to: $1.lab) }!
                    let match = ColorMatcher.nearest(to: target, in: palette)
                    let ranked = ColorMatcher.rankedCandidates(for: target, in: palette)
                    #expect(match == expected)
                    #expect(ranked.first == match)
                    #expect(Set(ranked.map(\.code)) == Set(palette.map(\.code)))
                }
            }
        }
    }

    @Test("every exact palette color remains an exact perceptual match")
    func exactPaletteColorsPreserved() {
        for palette in [MardPalette.standard221, MardPalette.allColors] {
            for color in palette {
                let match = ColorMatcher.nearest(to: color.lab, in: palette)
                #expect(match.lab.distance(to: color.lab) < 0.000001)
                #expect(palette.contains(match))
            }
        }
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

    @Test("a pale target retains its tone when a nearby pale candidate exists")
    func paleTargetPrefersNearbyPaleCandidate() {
        let target = LabColor(red: 0.95, green: 0.9, blue: 0.92) // pale pink
        let palette = [
            MardColor(code: "DARK", hex: "1A0A0D"), // near-black, would win on raw distance to a saturated version
            MardColor(code: "LIGHT", hex: "FFE8ED"), // pale pink, correct lightness class
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "LIGHT")
    }

    @Test("a dark target retains its tone when a nearby dark candidate exists")
    func darkTargetPrefersDarkCandidate() {
        let target = LabColor(red: 0.08, green: 0.05, blue: 0.06)
        let palette = [
            MardColor(code: "LIGHT", hex: "FFEEF0"),
            MardColor(code: "DARK", hex: "200E10"),
        ]
        let match = ColorMatcher.nearest(to: target, in: palette)
        #expect(match.code == "DARK")
    }

    @Test("a saturated target can use a closer muted bead to preserve its perceptual tone")
    func closerMutedCandidatePreservesTone() {
        let target = LabColor(red: 0.7, green: 0.098, blue: 0.098)
        let palette = [
            MardColor(code: "MUTED", hex: "7D2828"),
            MardColor(code: "VIVID", hex: "5A0005"),
        ]
        #expect(target.distance(to: palette[0].lab) < target.distance(to: palette[1].lab))
        #expect(ColorMatcher.nearest(to: target, in: palette).code == "MUTED")
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

    @Test("sparse palettes use perceptual distance rather than a hard hue cutoff")
    func sparsePaletteUsesPerceptualDistance() {
        let target = LabColor(red: 0.1, green: 0.3, blue: 0.75)
        let palette = [
            MardColor(code: "ORANGE", hex: "AB6351"),
            MardColor(code: "CYAN", hex: "005A3F"),
        ]
        #expect(target.distance(to: palette[0].lab) < target.distance(to: palette[1].lab))
        #expect(ColorMatcher.nearest(to: target, in: palette).code == "ORANGE")
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

    @Test("rankedCandidates returns all allowed candidates sorted by distance, nearest first")
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
