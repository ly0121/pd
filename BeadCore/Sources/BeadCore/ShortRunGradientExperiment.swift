/// An opt-in experiment only. PatternGenerator does not call this type.
/// `sourceStats` are SLIC means, not evidence that every original pixel is smooth.
/// The four-argument API returns unchanged without `sourceImage`: SLIC means
/// alone cannot establish whether actual source pixels conceal details.
public enum ShortRunGradientExperiment {
    public struct Change: Sendable {
        public let index: Int
        public let oldCode: String
        public let newCode: String
        public let oldError: Double
        public let newError: Double
        public let reason: String
    }

    public struct Result: Sendable {
        public let grid: BeadGrid
        public let changes: [Change]
        /// Structurally eligible short bands, before source/palette/error gates.
        public let eligibleSegments: Int
        /// Distinct (cell, palette color) proposals before budget and conflict resolution.
        public let feasibleCandidates: Int

        init(grid: BeadGrid, changes: [Change], eligibleSegments: Int = 0,
             feasibleCandidates: Int = 0) {
            self.grid = grid
            self.changes = changes
            self.eligibleSegments = eligibleSegments
            self.feasibleCandidates = feasibleCandidates
        }
    }

    private struct Proposal {
        let index: Int
        let run: Int
        let color: MardColor
        let paletteIndex: Int
        let oldError: Double
        let newError: Double
        let improvement: Double
    }

    public static func propose(
        _ grid: BeadGrid,
        sourceStats: [CellStats],
        palette: [MardColor],
        protected: Set<Int>,
        maxErrorIncrease: Double = 2.0,
        maxChangedFraction: Double = 0.01,
        sourceImage: PixelImage? = nil
    ) -> Result {
        let count = grid.colors.count
        guard count > 0, grid.columns > 0, grid.rows > 0, sourceStats.count == count,
              maxErrorIncrease.isFinite, maxErrorIncrease >= 0,
              maxChangedFraction.isFinite, maxChangedFraction > 0,
              let sourceImage, sourceImage.width >= grid.columns,
              sourceImage.height >= grid.rows
        else { return Result(grid: grid, changes: []) }

        let fixed = Set(grid.colors.indices.filter {
            grid.colors[$0] == .empty || grid.colors[$0].code == "H1"
        }).union(protected.filter { (0..<count).contains($0) })
        let eligible = count - fixed.count
        guard eligible > 0 else { return Result(grid: grid, changes: []) }
        let fraction = min(maxChangedFraction, 1)
        let limit = min(eligible, max(1, Int((Double(eligible) * fraction).rounded(.down))))
        let directions = [(step: 1, lines: grid.rows, length: grid.columns, horizontal: true),
                          (step: grid.columns, lines: grid.columns, length: grid.rows, horizontal: false)]
        var proposals: [Proposal] = []
        var eligibleSegments = 0
        var runID = 0

        for direction in directions {
            for line in 0..<direction.lines {
                let start = direction.horizontal ? line * grid.columns : line
                func cell(_ position: Int) -> Int { start + position * direction.step }
                var position = 0
                while position < direction.length {
                    let begin = position
                    let bead = grid.colors[cell(begin)]
                    while position < direction.length && grid.colors[cell(position)] == bead { position += 1 }
                    let end = position - 1
                    defer { runID += 1 }
                    guard (2...5).contains(position - begin), begin > 0,
                          position < direction.length else { continue }
                    let before = cell(begin - 1), after = cell(position)
                    // A short color band between identical surrounding tones is the only
                    // pattern considered; genuine A-to-B transitions are left alone.
                    guard grid.colors[before] == grid.colors[after],
                          grid.colors[before] != bead else { continue }
                    eligibleSegments += 1
                    let positions = Array((begin - 1)...position).map(cell)
                    guard positions.allSatisfy({ index in
                        !fixed.contains(index) && sourceStats[index].pixelCount > 0 &&
                        sourceStats[index].contourFraction.isFinite &&
                        sourceStats[index].contourFraction < 0.18 &&
                        finite(sourceStats[index].color) &&
                        rectangleIsSmooth(index, grid: grid, source: sourceImage)
                    }) else { continue }
                    // All source steps must be gentle, including both ends of the band.
                    guard zip(positions, positions.dropFirst()).allSatisfy({ left, right in
                        sourceStats[left].color.distance(to: sourceStats[right].color) <= 4 &&
                        rawBoundaryIsSmooth(left, right, grid: grid, source: sourceImage)
                    }) else { continue }
                    for index in Set([cell(begin), cell(end)]).sorted() {
                        let previous = index - direction.step, next = index + direction.step
                        // Fixed beads, holes and H1 also protect their orthogonal neighbors.
                        guard orthogonal(index, grid: grid).allSatisfy({ !fixed.contains($0) }),
                              [previous, next].allSatisfy({ !fixed.contains($0) }) else { continue }
                        let old = grid.colors[index]
                        let source = sourceStats[index].color
                        let oldError = source.distance(to: old.lab)
                        let oldJump = excessJump(index: index, bead: old, grid: grid,
                                                 stats: sourceStats, previous: previous, next: next)
                        for (paletteIndex, color) in palette.enumerated() where color != .empty &&
                            color.code != "H1" && color != old {
                            // The proposed shade must truly lie between both adjacent bead
                            // lightnesses, rather than merely swapping the abrupt boundary.
                            let lower = min(grid.colors[previous].lab.l, grid.colors[next].lab.l)
                            let upper = max(grid.colors[previous].lab.l, grid.colors[next].lab.l)
                            guard color.lab.l > lower + 0.0001 &&
                                  color.lab.l < upper - 0.0001 else { continue }
                            let newError = source.distance(to: color.lab)
                            let improvement = oldJump - excessJump(index: index, bead: color,
                                grid: grid, stats: sourceStats, previous: previous, next: next)
                            guard newError.isFinite, newError - oldError <= maxErrorIncrease,
                                  improvement.isFinite, improvement > 1e-9 else { continue }
                            proposals.append(Proposal(index: index, run: runID, color: color,
                                paletteIndex: paletteIndex, oldError: oldError,
                                newError: newError, improvement: improvement))
                        }
                    }
                }
            }
        }
        // Deterministic priority: source error tradeoff, visual improvement, palette order,
        // then row-major index. All proposals were calculated from the ORIGINAL grid.
        proposals.sort { lhs, rhs in
            let l = lhs.newError - lhs.oldError, r = rhs.newError - rhs.oldError
            if l != r { return l < r }
            if lhs.improvement != rhs.improvement { return lhs.improvement > rhs.improvement }
            if lhs.paletteIndex != rhs.paletteIndex { return lhs.paletteIndex < rhs.paletteIndex }
            return lhs.index < rhs.index
        }
        var output = grid
        var changes: [Change] = []
        var usedRuns = Set<Int>()
        var usedCells = Set<Int>()
        for proposal in proposals {
            if changes.count == limit { break }
            if usedRuns.contains(proposal.run) || usedCells.contains(proposal.index) ||
               orthogonal(proposal.index, grid: grid).contains(where: { usedCells.contains($0) }) {
                continue
            }
            usedRuns.insert(proposal.run)
            usedCells.insert(proposal.index)
            let old = grid.colors[proposal.index]
            output.colors[proposal.index] = proposal.color
            changes.append(Change(index: proposal.index, oldCode: old.code,
                newCode: proposal.color.code, oldError: proposal.oldError,
                newError: proposal.newError,
                reason: "source-smooth 2–5-cell band; reduced excess directional bead jump"))
        }
        changes.sort { $0.index < $1.index }
        return Result(grid: output, changes: changes, eligibleSegments: eligibleSegments,
                      feasibleCandidates: proposals.count)
    }

    private static func finite(_ lab: LabColor) -> Bool {
        lab.l.isFinite && lab.a.isFinite && lab.b.isFinite
    }

    private static func excessJump(index: Int, bead: MardColor, grid: BeadGrid,
                                   stats: [CellStats], previous: Int, next: Int) -> Double {
        [previous, next].reduce(0) { sum, neighbor in
            sum + max(0, bead.lab.distance(to: grid.colors[neighbor].lab) -
                          stats[index].color.distance(to: stats[neighbor].color))
        }
    }

    private static func orthogonal(_ index: Int, grid: BeadGrid) -> [Int] {
        let col = index % grid.columns, row = index / grid.columns
        var neighbors: [Int] = []
        if col > 0 { neighbors.append(index - 1) }
        if col + 1 < grid.columns { neighbors.append(index + 1) }
        if row > 0 { neighbors.append(index - grid.columns) }
        if row + 1 < grid.rows { neighbors.append(index + grid.columns) }
        return neighbors
    }

    /// Inspect corresponding original border pixels rather than trusting SLIC cell means.
    private static func rawBoundaryIsSmooth(_ left: Int, _ right: Int, grid: BeadGrid,
                                            source: PixelImage) -> Bool {
        let horizontal = right == left + 1 && left / grid.columns == right / grid.columns
        let vertical = right == left + grid.columns
        guard horizontal || vertical else { return false }
        let col = left % grid.columns, row = left / grid.columns
        let x0 = (col * source.width + grid.columns - 1) / grid.columns
        let x1 = ((col + 1) * source.width + grid.columns - 1) / grid.columns
        let y0 = (row * source.height + grid.rows - 1) / grid.rows
        let y1 = ((row + 1) * source.height + grid.rows - 1) / grid.rows
        if horizontal {
            guard x1 < source.width else { return false }
            for y in y0..<y1 {
                if source.pixel(x: x1 - 1, y: y).distance(to: source.pixel(x: x1, y: y)) > 6 {
                    return false
                }
            }
        } else {
            guard y1 < source.height else { return false }
            for x in x0..<x1 {
                if source.pixel(x: x, y: y1 - 1).distance(to: source.pixel(x: x, y: y1)) > 6 {
                    return false
                }
            }
        }
        return true
    }

    /// Inspect original fixed rectangles, not SLIC labels/means: a stripe can average out.
    /// A 6-ΔE76 within-cell range is deliberately conservative for this experiment.
    private static func rectangleIsSmooth(_ index: Int, grid: BeadGrid,
                                          source: PixelImage) -> Bool {
        let col = index % grid.columns, row = index / grid.columns
        let x0 = (col * source.width + grid.columns - 1) / grid.columns
        let x1 = ((col + 1) * source.width + grid.columns - 1) / grid.columns
        let y0 = (row * source.height + grid.rows - 1) / grid.rows
        let y1 = ((row + 1) * source.height + grid.rows - 1) / grid.rows
        guard x1 > x0, y1 > y0 else { return false }
        var pixels: [LabColor] = []
        for y in y0..<y1 {
            for x in x0..<x1 {
                let pixel = source.pixel(x: x, y: y)
                guard finite(pixel), pixels.allSatisfy({ $0.distance(to: pixel) <= 6 })
                else { return false }
                pixels.append(pixel)
            }
        }
        return true
    }
}
