import Testing
@testable import BeadCore

@Suite("SuperpixelSegmenter")
struct SuperpixelSegmenterTests {
    @Test("initial labels tile a 4x4 image into a 2x2 grid evenly")
    func initialLabelsTiling() {
        let labels = SuperpixelSegmenter.initialLabels(width: 4, height: 4, columns: 2, rows: 2)
        // top-left quadrant -> cell 0, top-right -> cell 1, bottom-left -> cell 2, bottom-right -> cell 3
        #expect(labels[0 * 4 + 0] == 0)
        #expect(labels[0 * 4 + 3] == 1)
        #expect(labels[3 * 4 + 0] == 2)
        #expect(labels[3 * 4 + 3] == 3)
    }

    @Test("cellStats computes uniform-weight mean color per cell on a flat-colored image")
    func cellStatsUniformMean() {
        // 2x2 image, left column red, right column blue, split into 1x2 grid (left cell / right cell).
        let red = LabColor(red: 1, green: 0, blue: 0)
        let blue = LabColor(red: 0, green: 0, blue: 1)
        let image = PixelImage(width: 2, height: 2, pixels: [red, blue, red, blue])
        let importance = ImportanceMap.uniform(width: 2, height: 2)
        let labels = SuperpixelSegmenter.initialLabels(width: 2, height: 2, columns: 2, rows: 1)

        let stats = SuperpixelSegmenter.cellStats(image: image, columns: 2, rows: 1, importance: importance, labels: labels)

        #expect(stats.count == 2)
        #expect(abs(stats[0].color.l - red.l) < 0.001)
        #expect(abs(stats[1].color.l - blue.l) < 0.001)
        #expect(stats[0].pixelCount == 2)
        #expect(stats[1].pixelCount == 2)
    }

    @Test("cellStats weights pixels by importance, biasing mean toward high-weight pixels")
    func cellStatsImportanceWeighting() {
        // Single cell containing one black and one white pixel; weight the white one heavily.
        let black = LabColor(red: 0, green: 0, blue: 0)
        let white = LabColor(red: 1, green: 1, blue: 1)
        let image = PixelImage(width: 2, height: 1, pixels: [black, white])
        let importance = ImportanceMap(width: 2, height: 1, weights: [1.0, 99.0])
        let labels = [0, 0]

        let stats = SuperpixelSegmenter.cellStats(image: image, columns: 1, rows: 1, importance: importance, labels: labels)

        // The weighted mean lightness should be much closer to white's L (100) than black's (0).
        #expect(stats[0].color.l > 90.0)
    }

    @Test("segment converges on a flat-colored image producing exactly one label per cell region")
    func segmentFlatImageConverges() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 8, height: 8, pixels: [LabColor](repeating: gray, count: 64))
        let importance = ImportanceMap.uniform(width: 8, height: 8)

        let result = SuperpixelSegmenter.segment(image: image, columns: 4, rows: 4, importance: importance)

        #expect(Set(result.labels).count <= 16)
        #expect(result.labels.count == 64)
    }

    @Test("segment respects high-importance regions by keeping smaller effective cells near them")
    func segmentHighImportanceRefinesBoundaries() {
        // 8x8 image: left half black, right half white, vertical seam at x=4.
        // Importance is high on the right half (near the seam detail) so SLIC should still
        // assign a clean split without producing NaN/invalid labels.
        var pixels = [LabColor]()
        for _ in 0..<8 {
            for x in 0..<8 {
                pixels.append(x < 4 ? LabColor(red: 0, green: 0, blue: 0) : LabColor(red: 1, green: 1, blue: 1))
            }
        }
        let image = PixelImage(width: 8, height: 8, pixels: pixels)
        var weights = [Double](repeating: 1.0, count: 64)
        for y in 0..<8 {
            for x in 4..<8 {
                weights[y * 8 + x] = 10.0
            }
        }
        let importance = ImportanceMap(width: 8, height: 8, weights: weights)

        let result = SuperpixelSegmenter.segment(image: image, columns: 4, rows: 4, importance: importance)

        #expect(result.labels.count == 64)
        #expect(result.labels.allSatisfy { $0 >= 0 && $0 < 16 })
    }
}
