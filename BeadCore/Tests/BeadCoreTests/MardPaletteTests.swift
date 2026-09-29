import Testing
@testable import BeadCore

@Suite("MardPalette")
struct MardPaletteTests {
    @Test("standard221 contains exactly the user's owned 90 colors")
    func totalCount() {
        #expect(MardPalette.standard221.count == 90)
    }

    @Test("standard221 has no duplicate codes")
    func noDuplicateCodes() {
        let codes = MardPalette.standard221.map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    @Test("each series has the expected count", arguments: [
        ("A", 16), ("B", 12), ("C", 12), ("D", 12),
        ("E", 13), ("F", 8), ("G", 12), ("H", 5),
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

    @Test("allColors contains exactly the full 221-color MARD lineup")
    func allColorsTotalCount() {
        #expect(MardPalette.allColors.count == 221)
    }

    @Test("allColors has no duplicate codes")
    func allColorsNoDuplicateCodes() {
        let codes = MardPalette.allColors.map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    @Test("allColors each series has the expected count", arguments: [
        ("A", 26), ("B", 32), ("C", 29), ("D", 26),
        ("E", 24), ("F", 25), ("G", 21), ("H", 23), ("M", 15),
    ])
    func allColorsSeriesCount(prefix: String, expectedCount: Int) {
        let seriesColors = MardPalette.allColors.filter { color in
            let letters = color.code.prefix { $0.isLetter }
            return letters == prefix
        }
        #expect(seriesColors.count == expectedCount)
    }

    @Test("every color in standard221 also exists in allColors")
    func standard221IsSubsetOfAllColors() {
        let allCodes = Set(MardPalette.allColors.map(\.code))
        #expect(MardPalette.standard221.allSatisfy { allCodes.contains($0.code) })
    }
}
