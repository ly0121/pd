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

    private var cellSize: CGFloat { 10 * scale }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Canvas { context, _ in
                for row in 0..<grid.rows {
                    for col in 0..<grid.columns {
                        let color = grid.color(col: col, row: row)
                        let rect = CGRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                        let isDimmed = highlightedColorCode != nil && highlightedColorCode != color.code
                        let uiColor = Color(red: color.red, green: color.green, blue: color.blue)
                        context.fill(Path(rect), with: .color(isDimmed ? uiColor.opacity(0.15) : uiColor))
                        context.stroke(Path(rect), with: .color(.black.opacity(0.08)), lineWidth: 0.5)
                    }
                }
            }
            .frame(width: CGFloat(grid.columns) * cellSize, height: CGFloat(grid.rows) * cellSize)
            .gesture(strokeGesture)
        }
        .gesture(magnificationGesture)
    }

    private var strokeGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let col = Int(value.location.x / cellSize)
                let row = Int(value.location.y / cellSize)
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
                scale = max(0.3, min(4.0, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
}
