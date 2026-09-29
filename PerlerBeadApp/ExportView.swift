import BeadCore
import SwiftUI

/// Renders a full export image: one cell per bead color with its MARD code printed inside, plus
/// row/column index labels along the top and left edges and a legend of every color code used
/// with its total count below the grid, laid out left-to-right and wrapping across rows (rather
/// than one color per line) so it doesn't stretch the exported image's height for large palettes.
/// This is intentionally separate from BeadPersistence's ThumbnailRenderer (which produces a
/// small, label-free preview for the project list) — the export needs to be legible enough to
/// actually bead from and shop from.
enum PatternExportRenderer {
    static func render(_ grid: BeadGrid, cellSize: CGFloat = 24) -> UIImage {
        let labelMargin: CGFloat = 28
        let legendRowHeight: CGFloat = 28
        let usages = ColorUsageCalculator.usages(for: grid)

        let gridWidth = CGFloat(grid.columns) * cellSize
        let gridHeight = CGFloat(grid.rows) * cellSize
        let canvasWidth = labelMargin + gridWidth
        let legendLayout = computeLegendLayout(usages, maxWidth: canvasWidth - 16, rowHeight: legendRowHeight)
        let legendHeight = CGFloat(legendLayout.rowCount) * legendRowHeight + 16

        let canvasSize = CGSize(width: canvasWidth, height: labelMargin + gridHeight + legendHeight)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            drawGrid(grid, cellSize: cellSize, origin: CGPoint(x: labelMargin, y: labelMargin), context: context.cgContext)
            drawLabels(grid, cellSize: cellSize, origin: CGPoint(x: labelMargin, y: labelMargin))
            drawLegend(legendLayout, origin: CGPoint(x: 8, y: labelMargin + gridHeight + 8))
        }
    }

    private static func drawGrid(_ grid: BeadGrid, cellSize: CGFloat, origin: CGPoint, context: CGContext) {
        // Below this cell size, the code text would just overlap into unreadable noise, so cells
        // fall back to color-only (still fine for reference — the legend below has the codes).
        let minCellSizeForCode: CGFloat = 10
        let showsCode = cellSize >= minCellSizeForCode
        let codeFontSize = min(max(cellSize * 0.32, 6), 14)
        let codeFont = UIFont.systemFont(ofSize: codeFontSize, weight: .medium)

        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let color = grid.color(col: col, row: row)
                let rect = CGRect(x: origin.x + CGFloat(col) * cellSize, y: origin.y + CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                guard color != .empty else {
                    // Punch a real transparent hole rather than leaving it painted white — the
                    // canvas background was already filled white before this loop runs, so
                    // skipping the fill alone would just leave a white square, not transparency.
                    context.clear(rect)
                    continue
                }
                UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
                context.fill(rect)
                UIColor.black.withAlphaComponent(0.15).setStroke()
                context.stroke(rect, width: 0.5)

                if showsCode {
                    drawCenteredCode(color.code, in: rect, font: codeFont, backgroundColor: color)
                }
            }
        }
    }

    /// Draws a color code centered in `rect`, choosing black or white text based on the
    /// perceptual luminance of `backgroundColor` so the code stays legible against light and
    /// dark bead colors alike (no reference palette to match against, so this is a standard
    /// relative-luminance contrast check rather than a fixed color).
    private static func drawCenteredCode(_ code: String, in rect: CGRect, font: UIFont, backgroundColor: MardColor) {
        let luminance = 0.299 * backgroundColor.red + 0.587 * backgroundColor.green + 0.114 * backgroundColor.blue
        let textColor: UIColor = luminance > 0.6 ? .black : .white

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = code.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        code.draw(at: textOrigin, withAttributes: attributes)
    }

    private static func drawLabels(_ grid: BeadGrid, cellSize: CGFloat, origin: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray,
        ]
        let labelInterval = max(1, grid.columns / 20)
        for col in stride(from: 0, to: grid.columns, by: labelInterval) {
            let text = "\(col + 1)"
            text.draw(at: CGPoint(x: origin.x + CGFloat(col) * cellSize + 2, y: origin.y - 16), withAttributes: attributes)
        }
        let rowLabelInterval = max(1, grid.rows / 20)
        for row in stride(from: 0, to: grid.rows, by: rowLabelInterval) {
            let text = "\(row + 1)"
            text.draw(at: CGPoint(x: 4, y: origin.y + CGFloat(row) * cellSize + 2), withAttributes: attributes)
        }
    }

    /// One legend entry ("[swatch] CODE ×count") positioned at a specific point, plus the total
    /// number of wrapped rows the whole legend occupies — computed once so render() can size the
    /// canvas before drawing, and drawLegend() can just place each entry where it was told to.
    private struct LegendEntryLayout {
        let usage: ColorUsage
        let origin: CGPoint
    }
    private struct LegendLayout {
        let entries: [LegendEntryLayout]
        let rowCount: Int
    }

    private static let legendFont = UIFont.systemFont(ofSize: 13)
    private static let legendSwatchSize: CGFloat = 20
    private static let legendEntrySpacing: CGFloat = 16

    /// Flows legend entries left-to-right, wrapping to a new row when the next entry would
    /// overflow `maxWidth` — this is what makes the legend read as a horizontal, wrapping strip
    /// instead of one color per line, which would make the exported image needlessly tall when
    /// a pattern uses many colors.
    private static func computeLegendLayout(_ usages: [ColorUsage], maxWidth: CGFloat, rowHeight: CGFloat) -> LegendLayout {
        var entries = [LegendEntryLayout]()
        var cursorX: CGFloat = 0
        var row = 0

        for usage in usages {
            let text = "\(usage.color.code)  ×\(usage.count)"
            let textWidth = text.size(withAttributes: [.font: legendFont]).width
            let entryWidth = legendSwatchSize + 8 + textWidth

            if cursorX > 0, cursorX + entryWidth > maxWidth {
                row += 1
                cursorX = 0
            }

            entries.append(LegendEntryLayout(usage: usage, origin: CGPoint(x: cursorX, y: CGFloat(row) * rowHeight)))
            cursorX += entryWidth + legendEntrySpacing
        }

        return LegendLayout(entries: entries, rowCount: usages.isEmpty ? 0 : row + 1)
    }

    /// Draws a swatch matching the actual bead color, its MARD code, and how many cells use it,
    /// at each entry's precomputed position — so the user knows what and how much to buy/prepare
    /// before starting to bead, without having to count cells in the grid themselves.
    private static func drawLegend(_ layout: LegendLayout, origin: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: legendFont,
            .foregroundColor: UIColor.black,
        ]
        for entry in layout.entries {
            let x = origin.x + entry.origin.x
            let y = origin.y + entry.origin.y
            let swatchRect = CGRect(x: x, y: y, width: legendSwatchSize, height: legendSwatchSize)
            UIColor(red: entry.usage.color.red, green: entry.usage.color.green, blue: entry.usage.color.blue, alpha: 1).setFill()
            UIBezierPath(rect: swatchRect).fill()
            UIColor.black.withAlphaComponent(0.2).setStroke()
            UIBezierPath(rect: swatchRect).stroke()
            let text = "\(entry.usage.color.code)  ×\(entry.usage.count)"
            text.draw(at: CGPoint(x: x + legendSwatchSize + 8, y: y + 2), withAttributes: attributes)
        }
    }
}
