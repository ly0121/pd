import Testing
@testable import BeadCore

@Suite("PaletteSampler")
struct PaletteSamplerTests {
    @Test("sample returns exactly the requested count when count is less than the palette size")
    func sampleReturnsRequestedCount() {
        let result = PaletteSampler.sample(count: 12, from: MardPalette.allColors)
        #expect(result.count == 12)
    }

    @Test("sample returns colors that are all members of the source palette")
    func sampleResultIsSubsetOfSourcePalette() {
        let source = MardPalette.allColors
        let sourceCodes = Set(source.map(\.code))
        let result = PaletteSampler.sample(count: 24, from: source)
        #expect(result.allSatisfy { sourceCodes.contains($0.code) })
    }

    @Test("sample returns no duplicate colors")
    func sampleHasNoDuplicates() {
        let result = PaletteSampler.sample(count: 48, from: MardPalette.allColors)
        let codes = result.map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    @Test("sample returns the full palette when count is greater than or equal to the palette size")
    func sampleReturnsFullPaletteWhenCountExceedsSize() {
        let source = MardPalette.standard221 // 90 colors
        let result = PaletteSampler.sample(count: 200, from: source)
        #expect(result.count == source.count)
    }

    @Test("sample returns the full palette when count exactly equals the palette size")
    func sampleReturnsFullPaletteWhenCountEqualsSize() {
        let source = MardPalette.standard221
        let result = PaletteSampler.sample(count: source.count, from: source)
        #expect(result.count == source.count)
    }

    @Test("sample returns an empty array when count is zero or negative")
    func sampleReturnsEmptyForNonPositiveCount() {
        #expect(PaletteSampler.sample(count: 0, from: MardPalette.allColors).isEmpty)
        #expect(PaletteSampler.sample(count: -5, from: MardPalette.allColors).isEmpty)
    }

    @Test("sample is deterministic across repeated calls with the same inputs")
    func sampleIsDeterministic() {
        let first = PaletteSampler.sample(count: 24, from: MardPalette.allColors)
        let second = PaletteSampler.sample(count: 24, from: MardPalette.allColors)
        #expect(first == second)
    }

    @Test("sample spreads results across the full hue range rather than clustering in one series")
    func sampleSpreadsAcrossHueRange() {
        let result = PaletteSampler.sample(count: 12, from: MardPalette.allColors)
        let hues = result.map(\.hsl.hue).sorted()
        // A representative spread should cover most of the 360-degree range, not bunch up in
        // a narrow band (which would happen if sampling just took the first N in declaration
        // order instead of sorting by hue first).
        let range = (hues.last ?? 0) - (hues.first ?? 0)
        #expect(range > 180)
    }
}
