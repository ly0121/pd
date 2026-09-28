import Testing
@testable import BeadCore

@Suite("MardPalette")
struct MardPaletteTests {
    @Test("standard221 contains exactly 221 colors")
    func totalCount() {
        #expect(MardPalette.standard221.count == 221)
    }

    @Test("standard221 has no duplicate codes")
    func noDuplicateCodes() {
        let codes = MardPalette.standard221.map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    @Test("each series has the expected count", arguments: [
        ("A", 26), ("B", 32), ("C", 29), ("D", 26),
        ("E", 24), ("F", 25), ("G", 21), ("H", 23), ("M", 15),
    ])
    func seriesCount(prefix: String, expectedCount: Int) {
        let seriesColors = MardPalette.standard221.filter { color in
            let letters = color.code.prefix { $0.isLetter }
            return letters == prefix
        }
        #expect(seriesColors.count == expectedCount)
    }

    @Test("H7 is pure black")
    func h7IsBlack() {
        let black = MardPalette.standard221.first { $0.code == "H7" }
        #expect(black?.red == 0.0)
        #expect(black?.green == 0.0)
        #expect(black?.blue == 0.0)
    }
}
