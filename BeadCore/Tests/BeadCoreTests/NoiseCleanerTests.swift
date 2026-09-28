import Testing
@testable import BeadCore

@Suite("NoiseCleaner")
struct NoiseCleanerTests {
    static let red = MardColor(code: "F1", hex: "FD957B")
    static let blue = MardColor(code: "C5", hex: "01ACEB")
    static let green = MardColor(code: "B5", hex: "35E352")

    @Test("single isolated pixel surrounded by one color is replaced by that color")
    func singleIsolatedPixelReplaced() {
        // 3x3 grid, all blue except the center pixel which is a lone red intruder.
        var colors = [MardColor](repeating: Self.blue, count: 9)
        colors[1 * 3 + 1] = Self.red // center
        let grid = BeadGrid(columns: 3, rows: 3, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned.color(col: 1, row: 1).code == Self.blue.code)
    }

    @Test("isolated pixel touching two different neighbor colors is left unchanged")
    func isolatedPixelWithMixedNeighborsUnchanged() {
        // Row of blue, green; red pixel at (1,1) touches both blue (left) and green (right)
        // among its neighbors, so it is not "surrounded by a single color" and stays put.
        let colors = [
            Self.blue, Self.blue, Self.blue,
            Self.blue, Self.red, Self.green,
            Self.blue, Self.green, Self.green,
        ]
        let grid = BeadGrid(columns: 3, rows: 3, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned.color(col: 1, row: 1).code == Self.red.code)
    }

    @Test("checkerboard pattern is left untouched because each color's total count is large")
    func checkerboardPatternUnchanged() {
        // 4x4 checkerboard: red and blue each appear 8 times, well above maxIsolatedCount.
        var colors = [MardColor]()
        for row in 0..<4 {
            for col in 0..<4 {
                colors.append((row + col) % 2 == 0 ? Self.red : Self.blue)
            }
        }
        let grid = BeadGrid(columns: 4, rows: 4, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned == grid)
    }

    @Test("edge pixel with only two neighbors, both matching, is replaced")
    func edgePixelWithTwoMatchingNeighborsReplaced() {
        // 1x3 grid: blue, red, blue. Red at index 1 has exactly two neighbors, both blue.
        let colors = [Self.blue, Self.red, Self.blue]
        let grid = BeadGrid(columns: 3, rows: 1, colors: colors)

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned.color(col: 1, row: 0).code == Self.blue.code)
    }

    @Test("grid with no isolated colors is returned unchanged")
    func noIsolatedColorsUnchanged() {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.red, Self.blue, Self.blue])

        let cleaned = NoiseCleaner.clean(grid)

        #expect(cleaned == grid)
    }
}
