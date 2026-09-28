import BeadCore
import SwiftUI

/// Renders a full export image: one cell per bead color, with grid lines and row/column index
/// labels along the top and left edges, plus a legend of color codes and usage counts below.
/// This is intentionally separate from BeadPersistence's ThumbnailRenderer (which produces a
/// small, label-free preview for the project list) — the export needs to be legible enough to
/// actually bead from.
enum PatternExportRenderer {
    static func render(_ grid: BeadGrid, cellSize: CGFloat = 24) -> UIImage {
        let labelMargin: CGFloat = 28
        let legendRowHeight: CGFloat = 28
        let usages = ColorUsageCalculator.usages(for: grid)
        let legendHeight = CGFloat(usages.count) * legendRowHeight + 16

        let gridWidth = CGFloat(grid.columns) * cellSize
        let gridHeight = CGFloat(grid.rows) * cellSize
        let canvasSize = CGSize(width: labelMargin + gridWidth, height: labelMargin + gridHeight + legendHeight)

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            drawGrid(grid, cellSize: cellSize, origin: CGPoint(x: labelMargin, y: labelMargin), context: context.cgContext)
            drawLabels(grid, cellSize: cellSize, origin: CGPoint(x: labelMargin, y: labelMargin))
            drawLegend(usages, origin: CGPoint(x: 8, y: labelMargin + gridHeight + 8), rowHeight: legendRowHeight)
        }
    }

    private static func drawGrid(_ grid: BeadGrid, cellSize: CGFloat, origin: CGPoint, context: CGContext) {
        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let color = grid.color(col: col, row: row)
                let rect = CGRect(x: origin.x + CGFloat(col) * cellSize, y: origin.y + CGFloat(row) * cellSize, width: cellSize, height: cellSize)
                UIColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).setFill()
                context.fill(rect)
                UIColor.black.withAlphaComponent(0.15).setStroke()
                context.stroke(rect, width: 0.5)
            }
        }
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

    private static func drawLegend(_ usages: [ColorUsage], origin: CGPoint, rowHeight: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.black,
        ]
        for (index, usage) in usages.enumerated() {
            let y = origin.y + CGFloat(index) * rowHeight
            let swatchRect = CGRect(x: origin.x, y: y, width: 20, height: 20)
            UIColor(red: usage.color.red, green: usage.color.green, blue: usage.color.blue, alpha: 1).setFill()
            UIBezierPath(rect: swatchRect).fill()
            let text = "\(usage.color.code)  ×\(usage.count)"
            text.draw(at: CGPoint(x: origin.x + 28, y: y + 2), withAttributes: attributes)
        }
    }
}

struct ExportView: View {
    let grid: BeadGrid
    let projectName: String
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let renderedImage {
                    Image(uiImage: renderedImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: renderedImage.size.width, height: renderedImage.size.height)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("导出图纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("分享") { showingShareSheet = true }
                        .disabled(renderedImage == nil)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let renderedImage {
                    ShareSheet(items: [renderedImage])
                }
            }
            .task {
                renderedImage = PatternExportRenderer.render(grid)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
