import Testing
@testable import BeadCore

@Suite("PaletteOptimizer")
struct PaletteOptimizerTests {
    @Test("flat black image optimizes every cell to the nearest black palette color")
    func flatImageOptimizesToSingleColor() {
        let black = LabColor(red: 0, green: 0, blue: 0)
        let image = PixelImage(width: 8, height: 8, pixels: [LabColor](repeating: black, count: 64))
        let importance = ImportanceMap.uniform(width: 8, height: 8)
        let palette = [
            MardColor(code: "H7", hex: "000000"),
            MardColor(code: "H1", hex: "FFFFFF"),
        ]

        let result = PaletteOptimizer.optimize(image: image, columns: 4, rows: 4, importance: importance, palette: palette)

        #expect(result.cellPaletteColors.allSatisfy { $0.code == "H7" })
    }

    @Test("two-color image assigns each half to its nearest respective palette color")
    func twoColorImageAssignsDistinctPaletteColors() {
        var pixels = [LabColor]()
        for _ in 0..<8 {
            for x in 0..<8 {
                pixels.append(x < 4 ? LabColor(red: 0, green: 0, blue: 0) : LabColor(red: 1, green: 1, blue: 1))
            }
        }
        let image = PixelImage(width: 8, height: 8, pixels: pixels)
        let importance = ImportanceMap.uniform(width: 8, height: 8)
        let palette = [
            MardColor(code: "H7", hex: "000000"),
            MardColor(code: "H1", hex: "FFFFFF"),
        ]

        let result = PaletteOptimizer.optimize(image: image, columns: 4, rows: 4, importance: importance, palette: palette)

        let usedCodes = Set(result.cellPaletteColors.map(\.code))
        #expect(usedCodes == ["H7", "H1"])
    }

    @Test("makeGrid produces a BeadGrid with matching dimensions and colors")
    func makeGridMatchesOptimizationResult() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 4, height: 4, pixels: [LabColor](repeating: gray, count: 16))
        let importance = ImportanceMap.uniform(width: 4, height: 4)
        let palette = [MardColor(code: "H3", hex: "B6B1BA")]

        let result = PaletteOptimizer.optimize(image: image, columns: 2, rows: 2, importance: importance, palette: palette)
        let grid = PaletteOptimizer.makeGrid(from: result)

        #expect(grid.columns == 2)
        #expect(grid.rows == 2)
        #expect(grid.colors == result.cellPaletteColors)
    }

    @Test("optimize terminates within the given iteration budget on a larger image")
    func optimizeTerminatesOnLargerImage() {
        var pixels = [LabColor]()
        for y in 0..<32 {
            for x in 0..<32 {
                let t = Double(x + y) / 64.0
                pixels.append(LabColor(red: t, green: 1 - t, blue: 0.5))
            }
        }
        let image = PixelImage(width: 32, height: 32, pixels: pixels)
        let importance = ImportanceMap.uniform(width: 32, height: 32)

        let result = PaletteOptimizer.optimize(
            image: image, columns: 8, rows: 8, importance: importance,
            palette: MardPalette.standard221, iterations: 10
        )

        #expect(result.cellPaletteColors.count == 64)
        #expect(result.segmentation.labels.count == 1024)
    }
}
