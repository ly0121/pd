import Testing
@testable import BeadCore

@Suite("ShortRunGradientExperiment")
struct ShortRunGradientExperimentTests {
    private let a = MardColor(code: "A", hex: "808080")
    private let middle = MardColor(code: "M", hex: "888888")
    private let b = MardColor(code: "B", hex: "909090")
    private let h1 = MardColor(code: "H1", hex: "FDFBFF")

    private func grid(_ colors: [MardColor], vertical: Bool = false) -> BeadGrid {
        BeadGrid(columns: vertical ? 1 : colors.count, rows: vertical ? colors.count : 1, colors: colors)
    }

    private func stats(_ lightness: [Double], contours: [Int] = [], empty: [Int] = []) -> [CellStats] {
        lightness.enumerated().map { index, l in
            CellStats(color: LabColor(l: l, a: a.lab.a, b: a.lab.b), centerX: Double(index),
                      centerY: 0, pixelCount: empty.contains(index) ? 0 : 1,
                      contourFraction: contours.contains(index) ? 0.18 : 0)
        }
    }

    private var ramp: [Double] {
        let base = a.lab.l
        return [base, base + 1, base + 2, base + 3, base + 4, base + 2, base]
    }

    private var band: [MardColor] { [a, a, b, b, b, a, a] }

    private func propose(_ grid: BeadGrid, sourceStats: [CellStats], palette: [MardColor],
                         protected: Set<Int>, maxErrorIncrease: Double = 2,
                         maxChangedFraction: Double = 0.01, sourceImage: PixelImage? = nil
    ) -> ShortRunGradientExperiment.Result {
        // One source pixel per cell is legitimate only for tests that do not inspect
        // intra-cell texture. Detail regressions supply their own multi-pixel image.
        let raw = sourceImage ?? PixelImage(width: grid.columns, height: grid.rows,
            pixels: sourceStats.count == grid.colors.count ? sourceStats.map(\.color) :
                [LabColor](repeating: a.lab, count: grid.colors.count))
        return ShortRunGradientExperiment.propose(grid, sourceStats: sourceStats,
            palette: palette, protected: protected, maxErrorIncrease: maxErrorIncrease,
            maxChangedFraction: maxChangedFraction, sourceImage: raw)
    }

    @Test("horizontal and vertical two-to-five-cell bands gain a source-aligned intermediate shade")
    func smoothBands() {
        for vertical in [false, true] {
            let input = grid(band, vertical: vertical)
            let evidence = stats(ramp)
            let result = propose(input, sourceStats: evidence,
                                                             palette: [a, middle, b], protected: [])
            #expect(result.changes.count == 1)
            #expect(result.changes[0].index == 2)
            #expect(result.changes[0].oldCode == "B")
            #expect(result.changes[0].newCode == "M")
            #expect(result.changes[0].newError - result.changes[0].oldError <= 2.0)
            #expect(!result.changes[0].reason.isEmpty)
            #expect(result.grid.colors[2] == middle)
            #expect(input.colors == band)
        }
    }

    @Test("two through five-cell bands admit only a feasible source-aligned boundary edit")
    func bandLengths() {
        for length in 2...5 {
            let colors = [a, a] + Array(repeating: b, count: length) + [a, a]
            let lightness = [a.lab.l, a.lab.l + 1] +
                (0..<length).map { a.lab.l + Double($0 + 2) } +
                [a.lab.l + Double(length + 1), a.lab.l + Double(length)]
            let input = grid(colors)
            let result = propose(input, sourceStats: stats(lightness),
                palette: [a, middle, b], protected: [])
            #expect(result.changes.count == 1, "length \(length)")
            if let change = result.changes.first {
                #expect(change.newCode == "M", "length \(length)")
                #expect(change.newError - change.oldError <= 2, "length \(length)")
            }
        }
    }

    @Test("no intermediate palette shade means no change")
    func noIntermediate() {
        let input = grid(band)
        #expect(propose(input, sourceStats: stats(ramp),
                                                   palette: [a, b], protected: []).grid == input)
    }

    @Test("actual hard source edge does not get smoothed")
    func realEdge() {
        let input = grid(band)
        let evidence = stats([a.lab.l, a.lab.l, b.lab.l, b.lab.l, b.lab.l, a.lab.l, a.lab.l])
        #expect(propose(input, sourceStats: evidence,
                                                   palette: [a, middle, b], protected: []).grid == input)
    }

    @Test("chromatic highlights and stripe-like source reversals are retained")
    func sourceDetail() {
        let input = grid(band)
        var chromatic = stats(ramp)
        chromatic[2].color = LabColor(l: ramp[2], a: a.lab.a + 20, b: a.lab.b)
        #expect(propose(input, sourceStats: chromatic,
                                                   palette: [a, middle, b], protected: []).grid == input)
        var striped = stats(ramp)
        striped[3].color = LabColor(l: ramp[3] + 12, a: a.lab.a, b: a.lab.b)
        #expect(propose(input, sourceStats: striped,
                                                   palette: [a, middle, b], protected: []).grid == input)
    }

    @Test("raw source rectangle rejects a thin stripe hidden by a smooth SLIC mean")
    func hiddenStripe() {
        let input = grid(band)
        let image = PixelImage(width: 7, height: 4, pixels: (0..<4).flatMap { y in
            (0..<7).map { x in
                LabColor(l: ramp[x] + ((x == 2 && y == 0) ? 15 : (x == 2 ? -5 : 0)),
                         a: a.lab.a, b: a.lab.b)
            }
        })
        let result = propose(input, sourceStats: stats(ramp),
            palette: [a, middle, b], protected: [], sourceImage: image)
        #expect(result.grid == input)
    }

    @Test("missing raw pixels cannot establish safe source detail")
    func requiresRawImage() {
        let input = grid(band)
        let result = ShortRunGradientExperiment.propose(input, sourceStats: stats(ramp),
            palette: [a, middle, b], protected: [])
        #expect(result.grid == input)
        #expect(result.changes.isEmpty)
    }

    @Test("subtle dark and light stripes can be farther apart than either is from first pixel")
    func pairwiseSourceDiameter() {
        let input = grid(band)
        let raw = PixelImage(width: 7, height: 3, pixels: (0..<3).flatMap { row in
            (0..<7).map { col in
                let offset = col == 2 ? [0.0, 4.0, -4.0][row] : 0.0
                return LabColor(l: ramp[col] + offset, a: a.lab.a, b: a.lab.b)
            }
        })
        let result = propose(input, sourceStats: stats(ramp),
            palette: [a, middle, b], protected: [], sourceImage: raw)
        #expect(result.grid == input)
    }

    @Test("non-divisible source width samples the same initial cell as the grid assignment")
    func nonDivisibleRectangle() {
        let input = grid(band)
        let image = PixelImage(width: 8, height: 1, pixels: (0..<8).map { x in
            LabColor(l: x == 3 ? ramp[2] + 20 : ramp[min(6, x * 7 / 8)],
                     a: a.lab.a, b: a.lab.b)
        })
        #expect(propose(input, sourceStats: stats(ramp), palette: [a, middle, b],
                        protected: [], sourceImage: image).grid == input)
    }

    @Test("seven source columns over three grid columns include pixel x=2 in first cell")
    func sevenByThreeCellOwnership() {
        var colors = [MardColor](repeating: a, count: 21)
        var lights = [Double](repeating: a.lab.l, count: 21)
        for row in 0..<7 {
            colors[row * 3] = band[row]
            lights[row * 3] = ramp[row]
        }
        let input = BeadGrid(columns: 3, rows: 7, colors: colors)
        let plain = PixelImage(width: 7, height: 7, pixels: (0..<7).flatMap { row in
            (0..<7).map { x in LabColor(l: x < 3 ? ramp[row] : a.lab.l,
                                         a: a.lab.a, b: a.lab.b) }
        })
        #expect(propose(input, sourceStats: stats(lights), palette: [a, middle, b],
                        protected: [], sourceImage: plain).changes.count == 1)
        let striped = PixelImage(width: 7, height: 7, pixels: (0..<7).flatMap { row in
            (0..<7).map { x in LabColor(l: x == 2 && row == 2 ? ramp[row] + 12 :
                                               (x < 3 ? ramp[row] : a.lab.l),
                                         a: a.lab.a, b: a.lab.b) }
        })
        #expect(propose(input, sourceStats: stats(lights), palette: [a, middle, b],
                        protected: [], sourceImage: striped).grid == input)
    }

    @Test("raw adjacent-cell edge is protected when SLIC means appear smooth")
    func rawCrossBoundary() {
        let input = grid(band)
        let image = PixelImage(width: 7, height: 1, pixels: (0..<7).map { x in
            LabColor(l: x == 1 ? ramp[1] - 8 : ramp[x], a: a.lab.a, b: a.lab.b)
        })
        #expect(propose(input, sourceStats: stats(ramp), palette: [a, middle, b],
                        protected: [], sourceImage: image).grid == input)
    }

    @Test("contours, zero-pixel stats and fixed neighborhoods veto the band edit")
    func protectedEvidence() {
        let input = grid(band)
        for index in [1, 2, 3] {
            for evidence in [stats(ramp, contours: [index]), stats(ramp, empty: [index])] {
                #expect(propose(input, sourceStats: evidence,
                    palette: [a, middle, b], protected: []).grid == input)
            }
            #expect(propose(input, sourceStats: stats(ramp),
                palette: [a, middle, b], protected: [index]).grid == input)
        }
        for sentinel in [h1, MardColor.empty] {
            var colors = band
            colors[1] = sentinel
            let altered = grid(colors)
            #expect(propose(altered, sourceStats: stats(ramp),
                palette: [a, middle, b, h1, .empty], protected: []).grid == altered)
        }
    }

    @Test("a B-aligned source band is not smoothed even with a relaxed error cap")
    func strictErrorCap() {
        let input = grid(band)
        let base = b.lab.l
        let source = stats([base - 4, base - 2, base, base, base, base - 2, base - 4])
        #expect(propose(input, sourceStats: source,
            palette: [a, middle, b], protected: []).grid == input)
        #expect(propose(input, sourceStats: source,
            palette: [a, middle, b], protected: [], maxErrorIncrease: 8).grid == input)
    }

    @Test("the one-percent edit cap is enforced")
    func limits() {
        var colors = [MardColor](repeating: a, count: 40 * 32)
        var lights = [Double](repeating: a.lab.l, count: colors.count)
        for row in 0..<32 {
            let origin = row * 40 + 6
            for offset in 0..<7 {
                colors[origin + offset] = band[offset]
                lights[origin + offset] = ramp[offset]
            }
        }
        let large = BeadGrid(columns: 40, rows: 32, colors: colors)
        let result = propose(large, sourceStats: stats(lights),
            palette: [a, middle, b], protected: [])
        #expect(result.changes.count > 0)
        #expect(result.changes.count <= 12)
        #expect(result.changes.map(\.index) == result.changes.map(\.index).sorted())
        #expect(result.changes.allSatisfy { $0.newError - $0.oldError <= 2.0 })
        #expect(large.colors == colors)
    }

    @Test("a protected orthogonal neighbor blocks an otherwise feasible band")
    func verticalFixedNeighbor() {
        var colors = [MardColor](repeating: a, count: 21)
        for index in 0..<7 { colors[7 + index] = band[index] }
        let input = BeadGrid(columns: 7, rows: 3, colors: colors)
        var lights = [Double](repeating: a.lab.l, count: 21)
        for index in 0..<7 { lights[7 + index] = ramp[index] }
        let evidence = stats(lights)
        #expect(propose(input, sourceStats: evidence,
            palette: [a, middle, b], protected: [2]).changes.allSatisfy { $0.index != 9 })
        #expect(propose(input, sourceStats: evidence,
            palette: [a, middle, b], protected: [2, 4]).grid == input)
        #expect(propose(input, sourceStats: evidence,
            palette: [a, middle, b], protected: []).changes.count == 1)
    }

    @Test("audit counts distinguish structural bands, feasible candidates and budgeted edits")
    func auditCounts() {
        let input = grid(band)
        let result = propose(input, sourceStats: stats(ramp),
            palette: [a, middle, b], protected: [])
        #expect(result.eligibleSegments == 1)
        #expect(result.feasibleCandidates >= 1)
        #expect(result.changes.count == 1)
        let insufficient = propose(input, sourceStats: stats(ramp),
            palette: [a, b], protected: [])
        #expect(insufficient.eligibleSegments == 1)
        #expect(insufficient.feasibleCandidates == 0)
    }

    @Test("budget denominator excludes fixed cells and retains one-edit fallback below 100")
    func fixedBudget() {
        var colors = [MardColor](repeating: a, count: 40 * 32)
        var lights = [Double](repeating: a.lab.l, count: colors.count)
        for row in 10..<32 {
            let origin = row * 40 + 6
            for offset in 0..<7 {
                colors[origin + offset] = band[offset]
                lights[origin + offset] = ramp[offset]
            }
        }
        let input = BeadGrid(columns: 40, rows: 32, colors: colors)
        let fixed = Set(0..<400)
        let result = propose(input, sourceStats: stats(lights),
            palette: [a, middle, b], protected: fixed)
        #expect(result.changes.count == 8) // floor(880 * 0.01)
        let small = propose(grid(band), sourceStats: stats(ramp),
            palette: [a, middle, b], protected: [])
        #expect(small.changes.count == 1) // floor(7 * 0.01), but nonempty minimum 1
    }

    @Test("identical Lab candidates select the first supplied palette entry deterministically")
    func paletteTies() {
        let first = MardColor(code: "M-FIRST", hex: "888888")
        let second = MardColor(code: "M-SECOND", hex: "888888")
        let input = grid(band)
        for _ in 0..<4 {
            let firstResult = propose(input, sourceStats: stats(ramp),
                palette: [a, first, second, b], protected: [])
            let secondResult = propose(input, sourceStats: stats(ramp),
                palette: [a, second, first, b], protected: [])
            #expect(firstResult.changes.map(\.newCode) == [first.code])
            #expect(secondResult.changes.map(\.newCode) == [second.code])
        }
    }

    @Test("invalid evidence or zero edit fraction never proposes changes")
    func invalidInput() {
        let input = grid(band)
        #expect(propose(input, sourceStats: [],
            palette: [a, middle, b], protected: []).grid == input)
        #expect(propose(input, sourceStats: stats(ramp),
            palette: [a, middle, b], protected: [], maxChangedFraction: 0).grid == input)
    }
}
