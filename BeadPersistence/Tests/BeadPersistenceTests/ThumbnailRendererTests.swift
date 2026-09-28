import BeadCore
import CoreGraphics
import ImageIO
import Testing
@testable import BeadPersistence

@Suite("ThumbnailRenderer")
struct ThumbnailRendererTests {
    static let red = MardColor(code: "F1", hex: "FD957B")
    static let blue = MardColor(code: "C5", hex: "01ACEB")

    @Test("render produces an image sized columns*cellSize by rows*cellSize")
    func renderProducesExpectedDimensions() {
        let grid = BeadGrid(columns: 3, rows: 2, colors: [MardColor](repeating: Self.red, count: 6))

        let image = ThumbnailRenderer.render(grid, cellSize: 4)

        #expect(image?.width == 12)
        #expect(image?.height == 8)
    }

    @Test("render returns nil for an empty grid")
    func renderReturnsNilForEmptyGrid() {
        let grid = BeadGrid(columns: 0, rows: 0, colors: [])

        let image = ThumbnailRenderer.render(grid, cellSize: 4)

        #expect(image == nil)
    }

    @Test("render draws row 0 at the top of the image despite CGContext's bottom-left origin")
    func renderPlacesRowZeroAtTop() {
        // 1x2 grid: row 0 red, row 1 blue. In image space (origin bottom-left), row 0 (top of
        // the logical grid) must land in the upper half of pixel rows, i.e. lower y-in-image-buffer
        // terms once we read back via a bitmap context.
        let grid = BeadGrid(columns: 1, rows: 2, colors: [Self.red, Self.blue])
        guard let image = ThumbnailRenderer.render(grid, cellSize: 2) else {
            Issue.record("expected non-nil image")
            return
        }

        var rawData = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &rawData, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // Top-left pixel of the readback buffer (row 0 in typical top-down bitmap indexing)
        // should be red (grid row 0), and bottom-left should be blue (grid row 1).
        let topLeftRed = rawData[0]
        let bottomLeftRowOffset = (image.height - 1) * image.width * 4
        let bottomLeftRed = rawData[bottomLeftRowOffset]

        #expect(topLeftRed > 200) // red channel high for the red MARD color
        #expect(bottomLeftRed < 100) // red channel low for the blue MARD color
    }

    @Test("renderPNGData produces valid, non-empty PNG bytes")
    func renderPNGDataProducesValidPNG() {
        let grid = BeadGrid(columns: 2, rows: 2, colors: [Self.red, Self.blue, Self.blue, Self.red])

        let data = ThumbnailRenderer.renderPNGData(grid, cellSize: 4)

        #expect(data != nil)
        #expect((data?.count ?? 0) > 0)
        // PNG magic bytes.
        #expect(data?.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) == true)
    }
}
