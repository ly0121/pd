import Foundation

/// Repairs local monotonicity breaks in quantized gradients: if the source image's tone changes
/// smoothly across a run of cells (e.g. a shaded sphere, a gradient background), the quantized
/// bead colors along that run should preserve the same "getting lighter" / "getting darker"
/// order — even though each cell was quantized independently and nothing in `PaletteOptimizer`
/// guarantees that on its own. This implements the user's "渐变区域维持原有深浅顺序" rule.
public enum GradientOrderEnforcer {
    /// Minimum number of cells in a run before it's treated as a genuine gradient rather than
    /// incidental noise.
    static let minRunLength = 4
    /// Minimum |ΔL| per consecutive step (in Lab L units) for a step to count toward extending a
    /// monotonic run.
    static let minStepDelta = 1.0

    /// `sourceStats` must be row-major with `grid.columns * grid.rows` entries, one per cell,
    /// giving that cell's mean source-image Lab color (as produced by `PaletteOptimizer`).
    public static func enforce(_ grid: BeadGrid, sourceStats: [CellStats], palette: [MardColor]) -> BeadGrid {
        precondition(sourceStats.count == grid.columns * grid.rows, "sourceStats must have one entry per cell")
        guard !palette.isEmpty else { return grid }

        var colors = grid.colors

        for row in 0..<grid.rows {
            let sourceRow = (0..<grid.columns).map { sourceStats[row * grid.columns + $0].color.l }
            let indices = (0..<grid.columns).map { row * grid.columns + $0 }
            enforceRuns(sourceValues: sourceRow, indices: indices, sourceColors: indices.map { sourceStats[$0].color }, colors: &colors, palette: palette)
        }

        for col in 0..<grid.columns {
            let sourceCol = (0..<grid.rows).map { sourceStats[$0 * grid.columns + col].color.l }
            let indices = (0..<grid.rows).map { $0 * grid.columns + col }
            enforceRuns(sourceValues: sourceCol, indices: indices, sourceColors: indices.map { sourceStats[$0].color }, colors: &colors, palette: palette)
        }

        return BeadGrid(columns: grid.columns, rows: grid.rows, colors: colors)
    }

    /// Finds monotonic runs in `sourceValues` and, within each, corrects any cell whose currently
    /// assigned color breaks the run's direction relative to the previous (already-corrected)
    /// cell — replacing it with the nearest rule-compliant candidate that restores the order.
    private static func enforceRuns(
        sourceValues: [Double],
        indices: [Int],
        sourceColors: [LabColor],
        colors: inout [MardColor],
        palette: [MardColor]
    ) {
        guard sourceValues.count >= 2 else { return }

        // stepDirections[k] describes the transition from cell k to cell k+1.
        let stepDirections = (0..<(sourceValues.count - 1)).map {
            stepDirection(sourceValues[$0], sourceValues[$0 + 1])
        }

        var stepIndex = 0
        while stepIndex < stepDirections.count {
            let direction = stepDirections[stepIndex]
            guard direction != 0 else {
                stepIndex += 1
                continue
            }
            var runEndStep = stepIndex
            while runEndStep < stepDirections.count && stepDirections[runEndStep] == direction {
                runEndStep += 1
            }
            // Steps [stepIndex, runEndStep) all share `direction`, connecting cells
            // [stepIndex, runEndStep] inclusive — that's (runEndStep - stepIndex + 1) cells.
            let runLength = runEndStep - stepIndex + 1
            if runLength >= minRunLength {
                fixRun(range: stepIndex..<(runEndStep + 1), direction: direction, indices: indices, sourceColors: sourceColors, colors: &colors, palette: palette)
            }
            stepIndex = runEndStep
        }
    }

    /// +1 if b is at least `minStepDelta` above a, -1 if at least that much below, 0 otherwise
    /// (too flat a step to count as continuing a gradient).
    private static func stepDirection(_ a: Double, _ b: Double) -> Int {
        let delta = b - a
        if delta >= minStepDelta { return 1 }
        if delta <= -minStepDelta { return -1 }
        return 0
    }

    private static func fixRun(
        range: Range<Int>,
        direction: Int,
        indices: [Int],
        sourceColors: [LabColor],
        colors: inout [MardColor],
        palette: [MardColor]
    ) {
        for position in (range.lowerBound + 1)..<range.upperBound {
            let idx = indices[position]
            let prevIdx = indices[position - 1]
            // Background-removed cells aren't beads at all, so they neither participate in nor
            // get overwritten by gradient-order repair: don't touch an EMPTY cell, and don't use
            // an EMPTY neighbor's (meaningless) lightness as the comparison basis.
            guard colors[idx] != .empty, colors[prevIdx] != .empty else { continue }

            let currentL = colors[idx].lab.l
            let prevL = colors[prevIdx].lab.l
            let violates = direction > 0 ? currentL < prevL : currentL > prevL
            guard violates else { continue }

            let candidates = ColorMatcher.rankedCandidates(for: sourceColors[position], in: palette)
            if let fixed = candidates.first(where: { candidate in
                let candidateL = candidate.lab.l
                return direction > 0 ? candidateL >= prevL : candidateL <= prevL
            }) {
                colors[idx] = fixed
            }
            // If no candidate satisfies the constraint, leave the original assignment — a
            // constrained palette (e.g. only 90 colors) may simply not have enough tonal
            // granularity to keep every gradient perfectly monotonic.
        }
    }
}
