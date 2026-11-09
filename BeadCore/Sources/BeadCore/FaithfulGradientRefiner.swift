/// Experimental only: not wired into PatternGenerator. All decisions read the original grid;
/// accepted replacements are written to a separate copy in row-major order.
public enum FaithfulGradientRefiner {
    public struct Change: Sendable {
        public let index: Int
        public let oldColor: MardColor
        public let newColor: MardColor
        /// New minus old source-to-bead Lab ΔE76 (may be positive, at most maxErrorIncrease).
        public let errorIncrease: Double
        /// Reduction of the sum of orthogonal bead-to-bead Lab ΔE76 jumps.
        public let neighborJumpReduction: Double
        public let reason: String
    }

    public struct Result: Sendable {
        public let grid: BeadGrid
        public let changes: [Change]
    }

    public static func refine(
        _ grid: BeadGrid,
        sourceStats: [CellStats],
        palette: [MardColor],
        protected: Set<Int>,
        maxErrorIncrease: Double = 2.0
    ) -> BeadGrid {
        refineWithChanges(grid, sourceStats: sourceStats, palette: palette,
                          protected: protected, maxErrorIncrease: maxErrorIncrease).grid
    }

    /// Returns auditable edits without altering the production generation path.
    public static func refineWithChanges(
        _ grid: BeadGrid,
        sourceStats: [CellStats],
        palette: [MardColor],
        protected: Set<Int>,
        maxErrorIncrease: Double = 2.0
    ) -> Result {
        let count = grid.colors.count
        guard count > 0, grid.columns > 0, grid.rows > 0,
              sourceStats.count == count, maxErrorIncrease.isFinite,
              maxErrorIncrease >= 0 else {
            return Result(grid: grid, changes: [])
        }

        // H1 is a real bead and may appear in the palette, unlike EMPTY. Neither is a candidate.
        let fixed = Set(grid.colors.indices.filter {
            grid.colors[$0] == .empty || grid.colors[$0].code == "H1"
        }).union(protected.filter { (0..<count).contains($0) })
        let eligibleCount = grid.colors.indices.filter { !fixed.contains($0) }.count
        let limit = min(eligibleCount, max(1, eligibleCount / 100))
        let paletteSet = Set(palette.filter { $0 != .empty && $0.code != "H1" })
        var output = grid
        var changes: [Change] = []

        for index in 0..<count {
            if changes.count >= limit { break }
            if fixed.contains(index) { continue }
            let neighbors = orthogonalNeighbors(of: index, columns: grid.columns, rows: grid.rows)
            if neighbors.count < 2 || neighbors.contains(where: { fixed.contains($0) }) { continue }
            let current = grid.colors[index]
            guard let candidate = neighbors.first.map({ grid.colors[$0] }),
                  current != candidate, paletteSet.contains(candidate),
                  neighbors.allSatisfy({ grid.colors[$0] == candidate }) else { continue }

            let participants = [index] + neighbors
            guard participants.allSatisfy({ sourceStats[$0].pixelCount > 0 &&
                                            sourceStats[$0].contourFraction < 0.18 }) else { continue }
            // Pairwise source evidence, including neighbor-to-neighbor comparisons, protects
            // bright chromatic edges and alternating texture not recognized as dark contours.
            let sources = participants.map { sourceStats[$0].color }
            guard sources.indices.allSatisfy({ i in
                sources.indices.dropFirst(i + 1).allSatisfy { j in
                    sources[i].distance(to: sources[j]) <= 4.0
                }
            }) else { continue }

            let source = sourceStats[index].color
            let oldError = source.distance(to: current.lab)
            let newError = source.distance(to: candidate.lab)
            let increase = newError - oldError
            let oldJump = current.lab.distance(to: candidate.lab) * Double(neighbors.count)
            let newJump = 0.0
            guard increase.isFinite, increase <= maxErrorIncrease,
                  oldJump.isFinite, oldJump > newJump else { continue }
            output.colors[index] = candidate
            changes.append(Change(index: index, oldColor: current, newColor: candidate,
                                  errorIncrease: increase,
                                  neighborJumpReduction: oldJump - newJump,
                                  reason: "smooth-source orthogonal isolated color"))
        }
        return Result(grid: output, changes: changes)
    }

    private static func orthogonalNeighbors(of index: Int, columns: Int, rows: Int) -> [Int] {
        let col = index % columns
        let row = index / columns
        var result: [Int] = []
        if row > 0 { result.append(index - columns) }
        if col > 0 { result.append(index - 1) }
        if col + 1 < columns { result.append(index + 1) }
        if row + 1 < rows { result.append(index + columns) }
        return result
    }
}
