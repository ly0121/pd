import Foundation

public struct JointOptimizationResult: Sendable, Equatable {
    public let segmentation: SegmentationResult
    public let cellPaletteColors: [MardColor]
}

public enum PaletteOptimizer {
    /// Runs SLIC-style region refinement and MARD palette assignment together: each iteration
    /// picks the nearest palette color per cell from the *current* region means, then refines
    /// region boundaries using those palette colors (not the raw means) as the color term, so
    /// boundaries settle around colors that actually exist in the palette rather than an
    /// intermediate average that no bead can represent.
    public static func optimize(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        palette: [MardColor],
        iterations: Int = 10,
        compactness: Double = 10.0
    ) -> JointOptimizationResult {
        precondition(!palette.isEmpty, "palette must not be empty")

        var labels = SuperpixelSegmenter.initialLabels(width: image.width, height: image.height, columns: columns, rows: rows)
        var stats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: labels)
        var paletteColors = stats.map { ColorMatcher.nearest(to: $0.color, in: palette) }

        for _ in 0..<iterations {
            let cellLabColors = paletteColors.map(\.lab)
            let newLabels = SuperpixelSegmenter.refine(
                image: image, columns: columns, rows: rows, importance: importance,
                labels: labels, cellColors: cellLabColors, centers: stats, compactness: compactness
            )
            let newStats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: newLabels, fallback: stats)
            let newPaletteColors = newStats.map { ColorMatcher.nearest(to: $0.color, in: palette) }

            let converged = newLabels == labels && newPaletteColors == paletteColors
            labels = newLabels
            stats = newStats
            paletteColors = newPaletteColors
            if converged {
                break
            }
        }

        return JointOptimizationResult(
            segmentation: SegmentationResult(columns: columns, rows: rows, labels: labels),
            cellPaletteColors: paletteColors
        )
    }

    public static func makeGrid(from result: JointOptimizationResult) -> BeadGrid {
        BeadGrid(columns: result.segmentation.columns, rows: result.segmentation.rows, colors: result.cellPaletteColors)
    }
}
