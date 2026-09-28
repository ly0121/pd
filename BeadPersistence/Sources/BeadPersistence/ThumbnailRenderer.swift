import BeadCore
import CoreGraphics
import Foundation

public enum ThumbnailRenderer {
    /// Renders a BeadGrid to a flat-color-per-cell CGImage at `cellSize` pixels per cell,
    /// suitable for a project list thumbnail. No grid lines or labels — those belong to the
    /// full export renderer (Plan C), not the lightweight list thumbnail.
    public static func render(_ grid: BeadGrid, cellSize: Int = 4) -> CGImage? {
        guard grid.columns > 0, grid.rows > 0, cellSize > 0 else { return nil }

        let width = grid.columns * cellSize
        let height = grid.rows * cellSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let color = grid.color(col: col, row: row)
                context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1.0)
                // Flip vertically: BeadGrid row 0 is the top row, but CGContext's origin is
                // bottom-left, so row 0 must be drawn at the highest y coordinate.
                let flippedRow = grid.rows - 1 - row
                context.fill(CGRect(x: col * cellSize, y: flippedRow * cellSize, width: cellSize, height: cellSize))
            }
        }

        return context.makeImage()
    }

    public static func renderPNGData(_ grid: BeadGrid, cellSize: Int = 4) -> Data? {
        guard let cgImage = render(grid, cellSize: cellSize) else { return nil }
        return CGImagePNGEncoder.encode(cgImage)
    }
}
