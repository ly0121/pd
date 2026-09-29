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

    @Test("a cell whose contourFraction clears the forcing threshold is assigned a dark palette color even though its own mean tone is light")
    func contourForcingOverridesLightMean() {
        // A light gray cell that would normally match a light palette color, but every pixel in
        // it is flagged as a strong contour so the assignment should be forced dark instead.
        let lightGray = LabColor(l: 80, a: 0, b: 0)
        let image = PixelImage(width: 4, height: 4, pixels: [LabColor](repeating: lightGray, count: 16))
        let importance = ImportanceMap.uniform(width: 4, height: 4)
        let contourWeights = [Double](repeating: 1.0, count: 16)
        let palette = [
            MardColor(code: "LIGHT", hex: "E0E0E0"),
            MardColor(code: "DARK", hex: "202020"),
        ]

        let result = PaletteOptimizer.optimize(
            image: image, columns: 1, rows: 1, importance: importance, palette: palette,
            contourWeights: contourWeights
        )

        #expect(result.cellPaletteColors.allSatisfy { $0.code == "DARK" })
    }

    @Test("a cell with no contour weight is unaffected by contour forcing and matches its natural class")
    func noContourWeightLeavesNaturalAssignmentUnchanged() {
        let lightGray = LabColor(l: 80, a: 0, b: 0)
        let image = PixelImage(width: 4, height: 4, pixels: [LabColor](repeating: lightGray, count: 16))
        let importance = ImportanceMap.uniform(width: 4, height: 4)
        let contourWeights = [Double](repeating: 0.0, count: 16)
        let palette = [
            MardColor(code: "LIGHT", hex: "E0E0E0"),
            MardColor(code: "DARK", hex: "202020"),
        ]

        let result = PaletteOptimizer.optimize(
            image: image, columns: 1, rows: 1, importance: importance, palette: palette,
            contourWeights: contourWeights
        )

        #expect(result.cellPaletteColors.allSatisfy { $0.code == "LIGHT" })
    }

    @Test("detected thin dark outlines survive averaging into a light cell")
    func detectedThinOutlineSurvivesAveraging() {
        let pixels = (0..<25).map { index in
            LabColor(l: index % 5 == 2 ? 10 : 90, a: 0, b: 0)
        }
        let image = PixelImage(width: 5, height: 5, pixels: pixels)
        let importance = ImportanceMap.uniform(width: 5, height: 5)
        let palette = [MardColor(code: "LIGHT", hex: "E0E0E0"), MardColor(code: "DARK", hex: "202020")]
        let natural = PaletteOptimizer.optimize(
            image: image, columns: 1, rows: 1, importance: importance, palette: palette, iterations: 0
        )
        let outlined = PaletteOptimizer.optimize(
            image: image, columns: 1, rows: 1, importance: importance, palette: palette, iterations: 0,
            contourWeights: ContourDetector.detect(image)
        )
        #expect(natural.cellPaletteColors.first?.code == "LIGHT")
        #expect(outlined.cellPaletteColors.first?.code == "DARK")
    }

    @Test("cellStats on the result exposes contourFraction matching the input contourWeights")
    func resultExposesCellStatsWithContourFraction() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 2, height: 2, pixels: [LabColor](repeating: gray, count: 4))
        let importance = ImportanceMap.uniform(width: 2, height: 2)
        let contourWeights = [0.1, 0.9, 0.5, 0.5] // mean 0.5
        let palette = [MardColor(code: "GRAY", hex: "808080")]

        let result = PaletteOptimizer.optimize(
            image: image, columns: 1, rows: 1, importance: importance, palette: palette,
            contourWeights: contourWeights
        )

        #expect(result.cellStats.count == 1)
        #expect(abs(result.cellStats[0].contourFraction - 0.5) < 0.001)
    }

    @Test("a cell whose foregroundFraction falls below the background removal threshold is assigned MardColor.empty")
    func backgroundRemovalAssignsEmptyBelowThreshold() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 4, height: 4, pixels: [LabColor](repeating: gray, count: 16))
        let importance = ImportanceMap.uniform(width: 4, height: 4)
        let foregroundWeights = [Double](repeating: 0.1, count: 16) // well below default threshold 0.3
        let palette = [MardColor(code: "GRAY", hex: "808080")]

        let result = PaletteOptimizer.optimize(
            image: image, columns: 1, rows: 1, importance: importance, palette: palette,
            foregroundWeights: foregroundWeights
        )

        #expect(result.cellPaletteColors.allSatisfy { $0 == MardColor.empty })
    }

    @Test("a cell whose foregroundFraction is at or above the background removal threshold matches normally")
    func foregroundCellMatchesNormallyAboveThreshold() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 4, height: 4, pixels: [LabColor](repeating: gray, count: 16))
        let importance = ImportanceMap.uniform(width: 4, height: 4)
        let foregroundWeights = [Double](repeating: 0.9, count: 16)
        let palette = [MardColor(code: "GRAY", hex: "808080")]

        let result = PaletteOptimizer.optimize(
            image: image, columns: 1, rows: 1, importance: importance, palette: palette,
            foregroundWeights: foregroundWeights
        )

        #expect(result.cellPaletteColors.allSatisfy { $0.code == "GRAY" })
    }

    @Test("omitting foregroundWeights entirely leaves normal palette matching unaffected")
    func omittingForegroundWeightsLeavesBehaviorUnchanged() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 4, height: 4, pixels: [LabColor](repeating: gray, count: 16))
        let importance = ImportanceMap.uniform(width: 4, height: 4)
        let palette = [MardColor(code: "GRAY", hex: "808080")]

        let result = PaletteOptimizer.optimize(image: image, columns: 1, rows: 1, importance: importance, palette: palette)

        #expect(result.cellPaletteColors.allSatisfy { $0.code == "GRAY" })
    }
}
