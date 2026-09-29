import Testing
@testable import BeadCore

@Suite("GradientOrderEnforcer")
struct GradientOrderEnforcerTests {
    /// Builds a 1-row grid where `sourceLValues[i]` is cell i's source-image mean lightness,
    /// and `colors[i]` is its (possibly rule-violating) currently assigned bead color.
    private static func makeSingleRowStats(sourceLValues: [Double]) -> [CellStats] {
        sourceLValues.enumerated().map { index, l in
            CellStats(color: LabColor(l: l, a: 0, b: 0), centerX: Double(index), centerY: 0, pixelCount: 1)
        }
    }

    @Test("a monotonically increasing gradient with one locally-reversed cell gets that cell corrected")
    func fixesLocalReversalInIncreasingGradient() {
        // Source lightness increases steadily: 10, 20, 30, 40, 50, 60 — a clear 6-cell run.
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [10, 20, 30, 40, 50, 60])
        // Bead colors mostly track that, but cell 3 (source L=40) was quantized to something
        // darker than cell 2 (source L=30) — a local reversal that breaks the increasing order.
        let palette = [
            MardColor(code: "L10", hex: "1A1A1A"), MardColor(code: "L20", hex: "333333"),
            MardColor(code: "L30", hex: "4D4D4D"), MardColor(code: "L40", hex: "666666"),
            MardColor(code: "L50", hex: "808080"), MardColor(code: "L60", hex: "999999"),
        ]
        let colors = [
            palette[0], palette[1], palette[2],
            palette[0], // reversal: darker than L30 even though source lightness increased
            palette[4], palette[5],
        ]
        let grid = BeadGrid(columns: 6, rows: 1, colors: colors)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        // The fix must be no darker than its predecessor (index 2, L30).
        #expect(fixed.color(col: 3, row: 0).lab.l >= colors[2].lab.l)
    }

    @Test("a monotonically decreasing gradient with one locally-reversed cell gets that cell corrected")
    func fixesLocalReversalInDecreasingGradient() {
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [60, 50, 40, 30, 20, 10])
        let palette = [
            MardColor(code: "L10", hex: "1A1A1A"), MardColor(code: "L20", hex: "333333"),
            MardColor(code: "L30", hex: "4D4D4D"), MardColor(code: "L40", hex: "666666"),
            MardColor(code: "L50", hex: "808080"), MardColor(code: "L60", hex: "999999"),
        ]
        let colors = [
            palette[5], palette[4], palette[3],
            palette[5], // reversal: lighter than the L40 predecessor even though source decreased
            palette[1], palette[0],
        ]
        let grid = BeadGrid(columns: 6, rows: 1, colors: colors)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed.color(col: 3, row: 0).lab.l <= colors[2].lab.l)
    }

    @Test("a run shorter than minRunLength is left untouched even if it contains a reversal")
    func shortRunIsNotTouched() {
        // Only 3 cells with an increasing trend — below minRunLength (4) — so even though
        // the middle assignment "reverses," enforce() should leave it as-is.
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [10, 20, 30])
        let palette = [
            MardColor(code: "L10", hex: "1A1A1A"), MardColor(code: "L20", hex: "333333"),
            MardColor(code: "L30", hex: "4D4D4D"),
        ]
        let colors = [palette[0], palette[2], palette[1]] // deliberately out of order
        let grid = BeadGrid(columns: 3, rows: 1, colors: colors)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed == grid)
    }

    @Test("a flat region (no consistent direction) is left untouched")
    func flatRegionIsUnchanged() {
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [50, 50, 50, 50, 50])
        let palette = [MardColor(code: "GRAY", hex: "808080")]
        let colors = [MardColor](repeating: palette[0], count: 5)
        let grid = BeadGrid(columns: 5, rows: 1, colors: colors)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed == grid)
    }

    @Test("an already-monotonic gradient is returned unchanged")
    func alreadyMonotonicGradientUnchanged() {
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [10, 20, 30, 40, 50])
        let palette = [
            MardColor(code: "L10", hex: "1A1A1A"), MardColor(code: "L20", hex: "333333"),
            MardColor(code: "L30", hex: "4D4D4D"), MardColor(code: "L40", hex: "666666"),
            MardColor(code: "L50", hex: "808080"),
        ]
        let grid = BeadGrid(columns: 5, rows: 1, colors: palette)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed == grid)
    }

    @Test("vertical gradients (columns) are corrected the same way as horizontal ones")
    func verticalGradientIsCorrected() {
        // 1 column, 6 rows, same increasing-lightness setup as the horizontal test.
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [10, 20, 30, 40, 50, 60])
        let palette = [
            MardColor(code: "L10", hex: "1A1A1A"), MardColor(code: "L20", hex: "333333"),
            MardColor(code: "L30", hex: "4D4D4D"), MardColor(code: "L40", hex: "666666"),
            MardColor(code: "L50", hex: "808080"), MardColor(code: "L60", hex: "999999"),
        ]
        let colors = [
            palette[0], palette[1], palette[2],
            palette[0], // reversal
            palette[4], palette[5],
        ]
        let grid = BeadGrid(columns: 1, rows: 6, colors: colors)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed.color(col: 0, row: 3).lab.l >= colors[2].lab.l)
    }

    @Test("enforce preserves grid dimensions")
    func enforcePreservesDimensions() {
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [10, 20, 30, 40])
        let palette = [MardColor(code: "GRAY", hex: "808080")]
        let colors = [MardColor](repeating: palette[0], count: 4)
        let grid = BeadGrid(columns: 4, rows: 1, colors: colors)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed.columns == grid.columns)
        #expect(fixed.rows == grid.rows)
    }

    @Test("a background-removed (EMPTY) cell in the middle of a gradient run is left as EMPTY, not overwritten with a color")
    func emptyCellInGradientRunStaysEmpty() {
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [10, 20, 30, 40, 50, 60])
        let palette = [
            MardColor(code: "L10", hex: "1A1A1A"), MardColor(code: "L20", hex: "333333"),
            MardColor(code: "L30", hex: "4D4D4D"), MardColor(code: "L40", hex: "666666"),
            MardColor(code: "L50", hex: "808080"), MardColor(code: "L60", hex: "999999"),
        ]
        let colors = [
            palette[0], palette[1], palette[2],
            .empty, // background-removed cell sitting inside an otherwise-monotonic run
            palette[4], palette[5],
        ]
        let grid = BeadGrid(columns: 6, rows: 1, colors: colors)

        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed.color(col: 3, row: 0) == .empty)
    }

    @Test("a reversal immediately after an EMPTY cell is still corrected, without using the EMPTY cell as the comparison basis")
    func reversalAfterEmptyCellIsStillCorrected() {
        let sourceStats = Self.makeSingleRowStats(sourceLValues: [10, 20, 30, 40, 50, 60])
        let palette = [
            MardColor(code: "L10", hex: "1A1A1A"), MardColor(code: "L20", hex: "333333"),
            MardColor(code: "L30", hex: "4D4D4D"), MardColor(code: "L40", hex: "666666"),
            MardColor(code: "L50", hex: "808080"), MardColor(code: "L60", hex: "999999"),
        ]
        let colors = [
            palette[0], palette[1], .empty,
            palette[0], // reversal relative to palette[2] (L30), which is now EMPTY at index 2
            palette[4], palette[5],
        ]
        let grid = BeadGrid(columns: 6, rows: 1, colors: colors)

        // Should not crash comparing against the EMPTY predecessor, and should leave index 3
        // untouched since fixRun's guard skips any pair involving an EMPTY neighbor.
        let fixed = GradientOrderEnforcer.enforce(grid, sourceStats: sourceStats, palette: palette)

        #expect(fixed.color(col: 2, row: 0) == .empty)
    }
}
