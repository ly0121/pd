import Foundation

public enum NoiseCleaner {
    /// Replaces isolated color blocks with the surrounding dominant color. A color is considered
    /// isolated when it appears in `maxIsolatedCount` or fewer cells *total* across the grid AND
    /// every one of its occurrences is fully surrounded (4-connected) by a single other color.
    /// This avoids false positives on large alternating patterns (e.g. checkerboards), where a
    /// color's total count is typically far above `maxIsolatedCount`.
    public static func clean(_ grid: BeadGrid, maxIsolatedCount: Int = 2) -> BeadGrid {
        var colorCounts: [String: Int] = [:]
        for color in grid.colors {
            colorCounts[color.code, default: 0] += 1
        }

        let isolatedCandidates = Set(colorCounts.filter { $0.value <= maxIsolatedCount }.keys)
        guard !isolatedCandidates.isEmpty else { return grid }

        var newColors = grid.colors
        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let color = grid.color(col: col, row: row)
                guard isolatedCandidates.contains(color.code) else { continue }

                var neighborColors = Set<String>()
                var neighborMard: [String: MardColor] = [:]
                let neighborOffsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
                for (dx, dy) in neighborOffsets {
                    let nx = col + dx
                    let ny = row + dy
                    guard nx >= 0, nx < grid.columns, ny >= 0, ny < grid.rows else { continue }
                    let neighbor = grid.color(col: nx, row: ny)
                    neighborColors.insert(neighbor.code)
                    neighborMard[neighbor.code] = neighbor
                }

                // Fully surrounded by a single other color: exactly one distinct neighbor code,
                // different from this cell's own color, and this cell has at least one neighbor
                // (guards against 1x1 grids where there are no neighbors to compare against).
                if neighborColors.count == 1, let onlyNeighborCode = neighborColors.first, onlyNeighborCode != color.code {
                    newColors[row * grid.columns + col] = neighborMard[onlyNeighborCode]!
                }
            }
        }

        return BeadGrid(columns: grid.columns, rows: grid.rows, colors: newColors)
    }
}
