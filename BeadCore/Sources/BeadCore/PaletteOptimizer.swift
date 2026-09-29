import Foundation

public struct JointOptimizationResult: Sendable, Equatable {
    public let segmentation: SegmentationResult
    public let cellPaletteColors: [MardColor]
    /// Per-cell stats (including `contourFraction`) from the final iteration, exposed so callers
    /// like `GradientOrderEnforcer` can reuse the same source-image measurements rather than
    /// recomputing them.
    public let cellStats: [CellStats]
}

public enum PaletteOptimizer {
    /// Runs SLIC-style region refinement and MARD palette assignment together: each iteration
    /// picks the nearest palette color per cell from the *current* region means, then refines
    /// region boundaries using those palette colors (not the raw means) as the color term, so
    /// boundaries settle around colors that actually exist in the palette rather than an
    /// intermediate average that no bead can represent.
    ///
    /// `contourWeights`, if supplied (one entry per source pixel, matching `image.pixels`),
    /// forces any cell whose `contourFraction` clears `contourForcingThreshold` to pick its
    /// palette color from the dark lightness class regardless of its own mean tone — this is
    /// what keeps beaded outlines dark per the user's "轮廓勾边保持深色" rule, instead of a thin
    /// dark line getting diluted into a lighter average once it's folded into a cell.
    ///
    /// `foregroundWeights`, if supplied, assigns `MardColor.empty` (no bead) to any cell whose
    /// `foregroundFraction` falls below `backgroundRemovalThreshold` instead of matching it
    /// against `palette` at all — this is background removal. Omitting `foregroundWeights`
    /// entirely (nil) means "background removal wasn't requested," which is different from every
    /// cell happening to score 0: with it omitted, `cellStats` never even computes
    /// `foregroundFraction`, so every cell keeps going through normal palette matching.
    public static func optimize(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        palette: [MardColor],
        iterations: Int = 10,
        compactness: Double = 10.0,
        contourWeights: [Double]? = nil,
        contourForcingThreshold: Double = 0.18,
        foregroundWeights: [Double]? = nil,
        backgroundRemovalThreshold: Double = 0.3
    ) -> JointOptimizationResult {
        precondition(!palette.isEmpty, "palette must not be empty")

        func paletteColor(for stat: CellStats) -> MardColor {
            if foregroundWeights != nil, stat.foregroundFraction < backgroundRemovalThreshold {
                return .empty
            }
            let forcedLightness: LightnessClass? = stat.contourFraction >= contourForcingThreshold ? .dark : nil
            return ColorMatcher.nearest(to: stat.color, in: palette, forcedLightness: forcedLightness)
        }

        var labels = SuperpixelSegmenter.initialLabels(width: image.width, height: image.height, columns: columns, rows: rows)
        var stats = SuperpixelSegmenter.cellStats(
            image: image, columns: columns, rows: rows, importance: importance, labels: labels,
            contourWeights: contourWeights, foregroundWeights: foregroundWeights
        )
        var paletteColors = stats.map(paletteColor)

        for _ in 0..<iterations {
            let cellLabColors = paletteColors.map(\.lab)
            let newLabels = SuperpixelSegmenter.refine(
                image: image, columns: columns, rows: rows, importance: importance,
                labels: labels, cellColors: cellLabColors, centers: stats, compactness: compactness
            )
            let newStats = SuperpixelSegmenter.cellStats(
                image: image, columns: columns, rows: rows, importance: importance, labels: newLabels,
                fallback: stats, contourWeights: contourWeights, foregroundWeights: foregroundWeights
            )
            let newPaletteColors = newStats.map(paletteColor)

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
            cellPaletteColors: paletteColors,
            cellStats: stats
        )
    }

    public static func makeGrid(from result: JointOptimizationResult) -> BeadGrid {
        BeadGrid(columns: result.segmentation.columns, rows: result.segmentation.rows, colors: result.cellPaletteColors)
    }
}
