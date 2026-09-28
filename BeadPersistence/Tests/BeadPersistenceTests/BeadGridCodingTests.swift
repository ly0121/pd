import BeadCore
import Testing
@testable import BeadPersistence

@Suite("BeadGridCoding")
struct BeadGridCodingTests {
    static let red = MardColor(code: "F1", hex: "FD957B")
    static let blue = MardColor(code: "C5", hex: "01ACEB")

    @Test("encode joins color codes in row-major order")
    func encodeJoinsCodesInOrder() {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.blue, Self.blue, Self.red])

        let encoded = BeadGridCoding.encode(grid)

        #expect(encoded == "F1,C5,C5,F1")
    }

    @Test("decode reconstructs a grid matching the original colors")
    func decodeRoundTripsColors() throws {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.blue, Self.blue, Self.red])
        let encoded = BeadGridCoding.encode(grid)

        let decoded = try BeadGridCoding.decode(encoded, columns: 2, rows: 2, palette: [Self.red, Self.blue])

        #expect(decoded == grid)
    }

    @Test("decode throws codeCountMismatch when the code count doesn't match columns * rows")
    func decodeThrowsOnCountMismatch() {
        #expect(throws: BeadGridCodingError.codeCountMismatch(expected: 4, actual: 2)) {
            try BeadGridCoding.decode("F1,C5", columns: 2, rows: 2, palette: [Self.red, Self.blue])
        }
    }

    @Test("decode throws unknownColorCode when a code isn't in the given palette")
    func decodeThrowsOnUnknownCode() {
        #expect(throws: BeadGridCodingError.unknownColorCode("Z99")) {
            try BeadGridCoding.decode("F1,Z99,C5,F1", columns: 2, rows: 2, palette: [Self.red, Self.blue])
        }
    }

    @Test("round-trip through the full MARD 221 palette preserves every color")
    func roundTripFullPalette() throws {
        let colors = MardPalette.standard221
        let grid = BeadGrid(columns: colors.count, rows: 1, colors: colors)
        let encoded = BeadGridCoding.encode(grid)

        let decoded = try BeadGridCoding.decode(encoded, columns: colors.count, rows: 1, palette: MardPalette.standard221)

        #expect(decoded == grid)
    }
}
