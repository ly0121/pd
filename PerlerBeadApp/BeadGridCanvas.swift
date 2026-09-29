import BeadCore
import SwiftUI

/// Renders a BeadGrid with SwiftUI's Canvas (immediate-mode drawing) rather than one view per
/// cell — a 200x200 grid is 40,000 cells, and 40,000 SwiftUI views would be prohibitively slow
/// to lay out and update on every edit.
struct BeadGridCanvas: View {
    let grid: BeadGrid
    let highlightedColorCode: String?
    /// Called for every cell touched during a stroke. `isStrokeStart` is true only for the very
    /// first cell of a given continuous touch — callers use this to record undo history exactly
    /// once per stroke rather than once per cell (which would make undo a no-op on drags) or
    /// once per gesture-end (which would record history *after* the edit already happened).
    var onCellTouched: ((Int, Int, _ isStrokeStart: Bool) -> Void)?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isStrokeInProgress = false
    /// The grid dimensions the current `scale` was fit to. Compared against the live grid so a
    /// regenerate at a different size re-fits, while rotation or other re-layouts at the same
    /// grid size leave the user's manual pinch-zoom alone.
    @State private var fittedGridKey: String?

    private let baseCellSize: CGFloat = 10
    private let minScale: CGFloat = 0.05
    private let maxScale: CGFloat = 4.0
    /// Fixed-size ruler strip along the top/left edges for row/column index labels — stays a
    /// constant width regardless of zoom (like a ruler), rather than scaling with `cellSize`.
    private let labelMargin: CGFloat = 24

    private var cellSize: CGFloat { baseCellSize * scale }
    private var gridKey: String { "\(grid.columns)x\(grid.rows)" }

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Canvas { context, _ in
                    for row in 0..<grid.rows {
                        for col in 0..<grid.columns {
                            let color = grid.color(col: col, row: row)
                            let rect = CGRect(x: labelMargin + CGFloat(col) * cellSize, y: labelMargin + CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                            guard color != .empty else { continue } // background-removed cell: leave transparent
                            let isDimmed = highlightedColorCode != nil && highlightedColorCode != color.code
                            let uiColor = Color(red: color.red, green: color.green, blue: color.blue)
                            context.fill(Path(rect), with: .color(isDimmed ? uiColor.opacity(0.15) : uiColor))
                            context.stroke(Path(rect), with: .color(.black.opacity(0.08)), lineWidth: 0.5)

                            if !isDimmed {
                                drawCenteredCode(color.code, in: rect, color: color, context: context)
                            }
                        }
                    }

                    drawRulerLabels(context: context)
                }
                .frame(width: labelMargin + CGFloat(grid.columns) * cellSize, height: labelMargin + CGFloat(grid.rows) * cellSize)
                .gesture(strokeGesture)
            }
            .gesture(magnificationGesture)
            .onAppear { fitToScreen(containerSize: proxy.size) }
            .onChange(of: gridKey) { _, _ in fitToScreen(containerSize: proxy.size) }
        }
    }

    /// Mirrors PatternExportRenderer.drawLabels: row/column indices at a spaced interval (never
    /// more than ~20 labels along either axis) so they stay legible instead of overlapping on
    /// large grids.
    private func drawRulerLabels(context: GraphicsContext) {
        let font = Font.system(size: 9)
        let colInterval = max(1, grid.columns / 20)
        for col in stride(from: 0, to: grid.columns, by: colInterval) {
            let text = Text("\(col + 1)").font(font).foregroundColor(.secondary)
            context.draw(text, at: CGPoint(x: labelMargin + CGFloat(col) * cellSize + 2, y: labelMargin / 2), anchor: .leading)
        }
        let rowInterval = max(1, grid.rows / 20)
        for row in stride(from: 0, to: grid.rows, by: rowInterval) {
            let text = Text("\(row + 1)").font(font).foregroundColor(.secondary)
            context.draw(text, at: CGPoint(x: labelMargin / 2, y: labelMargin + CGFloat(row) * cellSize + 2), anchor: .leading)
        }
    }

    /// Mirrors PatternExportRenderer.drawCenteredCode: chooses black or white text based on the
    /// cell's perceptual luminance so the code stays legible against light and dark bead colors
    /// alike.
    private func drawCenteredCode(_ code: String, in rect: CGRect, color: MardColor, context: GraphicsContext) {
        let luminance = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
        let textColor: Color = luminance > 0.6 ? .black : .white
        let fontSize = min(max(cellSize * 0.32, 6), 14)
        let text = Text(code).font(.system(size: fontSize, weight: .medium)).foregroundColor(textColor)
        context.draw(text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
    }

    /// Sets the initial zoom so the whole grid fits within the visible canvas area (never
    /// zooming in past 1:1), rather than always starting at a fixed 10pt/cell that clips large
    /// grids to a corner until the user manually pinches out.
    private func fitToScreen(containerSize: CGSize) {
        guard fittedGridKey != gridKey, containerSize.width > 0, containerSize.height > 0 else { return }
        fittedGridKey = gridKey
        let fitWidth = (containerSize.width - labelMargin) / (CGFloat(grid.columns) * baseCellSize)
        let fitHeight = (containerSize.height - labelMargin) / (CGFloat(grid.rows) * baseCellSize)
        let fitScale = max(minScale, min(fitWidth, fitHeight, 1.0))
        scale = fitScale
        lastScale = fitScale
    }

    private var strokeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let col = Int((value.location.x - labelMargin) / cellSize)
                let row = Int((value.location.y - labelMargin) / cellSize)
                guard col >= 0, col < grid.columns, row >= 0, row < grid.rows else { return }
                onCellTouched?(col, row, !isStrokeInProgress)
                isStrokeInProgress = true
            }
            .onEnded { _ in
                isStrokeInProgress = false
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(minScale, min(maxScale, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
}
