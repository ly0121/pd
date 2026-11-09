import Testing
@testable import BeadCore

@Suite("Prepared palette equivalence")
struct PreparedPaletteTests {
    @Test("duplicate candidates and exact distance ties retain first palette entry")
    func tiesAndDuplicates() {
        let first = MardColor(code: "FIRST", hex: "808080")
        let second = MardColor(code: "SECOND", hex: "808080")
        let palette = [first, second, first, second]
        let target = first.lab
        let prepared = PreparedPalette(palette)
        #expect(prepared.nearest(to: target) == first)
        #expect(prepared.nearest(to: target, forcedLightness: .dark) ==
                ColorMatcher.nearest(to: target, in: palette, forcedLightness: .dark))
        #expect(prepared.nearest(to: target) == ColorMatcher.nearest(to: target, in: palette))
    }

    @Test("forced dark candidates and absent-class fallback preserve legacy selection")
    func darkSubsetAndFallback() {
        let light = MardColor(code: "LIGHT", hex: "FFFFFF")
        let dark = MardColor(code: "DARK", hex: "101010")
        let target = light.lab
        let mixed = [light, dark, dark]
        #expect(PreparedPalette(mixed).nearest(to: target, forcedLightness: .dark) == dark)
        #expect(PreparedPalette([dark, light]).nearest(to: dark.lab, forcedLightness: .light) == light)
        for palette in [[light], [light, light], [dark]] {
            for forced: LightnessClass? in [nil, .dark, .light] {
                #expect(PreparedPalette(palette).nearest(to: target, forcedLightness: forced) ==
                        ColorMatcher.nearest(to: target, in: palette, forcedLightness: forced))
            }
        }
    }

    @Test("single, sampled, owned and full palette sizes agree with legacy matching")
    func paletteSizes() {
        let h1 = MardPalette.allColors.first { $0.code == "H1" }!
        let palettes = [[h1], PaletteSampler.sample(count: 12, from: MardPalette.standard221),
                        MardPalette.standard221, MardPalette.allColors]
        let targets = [LabColor(red: 0, green: 0, blue: 0),
                       LabColor(red: 0.49, green: 0.52, blue: 0.62),
                       LabColor(red: 1, green: 1, blue: 1)]
        for palette in palettes {
            let prepared = PreparedPalette(palette)
            for target in targets {
                for forced: LightnessClass? in [nil, .dark, .light] {
                    #expect(prepared.nearest(to: target, forcedLightness: forced) ==
                            ColorMatcher.nearest(to: target, in: palette, forcedLightness: forced))
                }
            }
        }
    }

    @Test("default iterative optimizer agrees with original matcher within the same process")
    func iterativeLegacyComparison() {
        let side = 40
        let columns = 10
        let palette = ["A14", "B8", "C7", "D15", "H1", "H7"].map { code in
            MardPalette.allColors.first { $0.code == code }!
        }
        let image = PixelImage(width: side, height: side, pixels: (0..<side * side).map { index in
            let x = index % side
            let y = index / side
            return palette[(x / 8 + y / 8 * 3) % palette.count].lab
        })
        let importance = ImportanceMap.uniform(width: side, height: side)
        let contour = (0..<side * side).map { $0 % side == 7 ? 1.0 : 0.0 }
        func legacyMatch(_ stat: CellStats) -> MardColor {
            ColorMatcher.nearest(to: stat.color, in: palette,
                forcedLightness: stat.contourFraction >= 0.18 ? .dark : nil)
        }
        var labels = SuperpixelSegmenter.initialLabels(width: side, height: side, columns: columns, rows: columns)
        var stats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: columns,
            importance: importance, labels: labels, contourWeights: contour)
        var colors = stats.map(legacyMatch)
        for _ in 0..<10 {
            let nextLabels = SuperpixelSegmenter.refine(image: image, columns: columns, rows: columns,
                importance: importance, labels: labels, cellColors: colors.map(\.lab), centers: stats)
            let nextStats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: columns,
                importance: importance, labels: nextLabels, fallback: stats, contourWeights: contour)
            let nextColors = nextStats.map(legacyMatch)
            let converged = nextLabels == labels && nextColors == colors
            labels = nextLabels
            stats = nextStats
            colors = nextColors
            if converged { break }
        }
        let actual = PaletteOptimizer.optimize(image: image, columns: columns, rows: columns,
            importance: importance, palette: palette, contourWeights: contour)
        #expect(actual.segmentation.labels == labels)
        #expect(actual.cellStats == stats)
        #expect(actual.cellPaletteColors == colors)
    }

    @Test("optimizer preserves legacy labels, final stats and empty cells")
    func optimizerLegacyComparison() {
        let width = 24
        let image = PixelImage(width: width, height: width, pixels: (0..<width * width).map { index in
            let x = index % width
            let y = index / width
            return LabColor(red: Double(x) / 30, green: Double(y) / 30, blue: 0.2)
        })
        let importance = ImportanceMap.uniform(width: width, height: width)
        let palette = [MardColor(code: "LIGHT", hex: "FFFFFF"),
                       MardColor(code: "DARK", hex: "101010"),
                       MardColor(code: "DUP", hex: "101010")]
        let contour = (0..<width * width).map { $0 % width < 2 ? 1.0 : 0.0 }
        let foreground = (0..<width * width).map { $0 / width < 4 ? 0.0 : 1.0 }
        func legacyMatch(_ stat: CellStats) -> MardColor {
            if stat.foregroundFraction < 0.3 { return .empty }
            return ColorMatcher.nearest(to: stat.color, in: palette,
                forcedLightness: stat.contourFraction >= 0.18 ? .dark : nil)
        }
        // Pre-refinement comparison isolates palette assignment from Set-order ties in refine.
        // Iterative grids are independently guarded by GenerationEquivalenceTests.
        let labels = SuperpixelSegmenter.initialLabels(width: width, height: width, columns: 6, rows: 6)
        let stats = SuperpixelSegmenter.cellStats(image: image, columns: 6, rows: 6,
            importance: importance, labels: labels, contourWeights: contour, foregroundWeights: foreground)
        let colors = stats.map(legacyMatch)
        let actual = PaletteOptimizer.optimize(image: image, columns: 6, rows: 6,
            importance: importance, palette: palette, iterations: 0,
            contourWeights: contour, foregroundWeights: foreground)
        #expect(actual.segmentation.labels == labels)
        #expect(actual.cellStats == stats)
        #expect(actual.cellPaletteColors == colors)
        #expect(colors.contains(.empty))
    }
}
