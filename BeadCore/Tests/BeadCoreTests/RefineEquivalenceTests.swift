import CoreGraphics
import Dispatch
import Foundation
import Testing
@testable import BeadCore

/// Frozen pre-optimization refine from SuperpixelSegmenter.swift (2026-11-10).
/// Intentionally retains the Set, strict comparison, and pow inside the candidate loop.
private func legacyRefine(
    image: PixelImage,
    columns: Int,
    rows: Int,
    importance: ImportanceMap,
    labels: [Int],
    cellColors: [LabColor],
    centers: [CellStats],
    compactness: Double = 10.0
) -> [Int] {
    let cellCount = columns * rows
    precondition(cellColors.count == cellCount && centers.count == cellCount)

    let spatialScale = (Double(image.width * image.height) / Double(cellCount)).squareRoot()
    let maxImportance = max(importance.weights.max() ?? 1.0, 0.0001)

    var newLabels = labels
    for y in 0..<image.height {
        for x in 0..<image.width {
            let idx = y * image.width + x
            let ownCell = labels[idx]
            let ownRow = ownCell / columns
            let ownCol = ownCell % columns

            var candidates: Set<Int> = [ownCell]
            if ownCol > 0 { candidates.insert(ownRow * columns + (ownCol - 1)) }
            if ownCol < columns - 1 { candidates.insert(ownRow * columns + (ownCol + 1)) }
            if ownRow > 0 { candidates.insert((ownRow - 1) * columns + ownCol) }
            if ownRow < rows - 1 { candidates.insert((ownRow + 1) * columns + ownCol) }

            let normalizedImportance = importance.weight(x: x, y: y) / maxImportance
            let effectiveCompactness = max(1.0, compactness * (1.0 - 0.6 * normalizedImportance))

            let pixelColor = image.pixels[idx]
            var bestCell = ownCell
            var bestDistance = Double.greatestFiniteMagnitude

            for cell in candidates {
                let colorDist = pixelColor.distance(to: cellColors[cell])
                let dx = Double(x) - centers[cell].centerX
                let dy = Double(y) - centers[cell].centerY
                let spatialDist = (dx * dx + dy * dy).squareRoot()
                let combined = (colorDist * colorDist) + pow(effectiveCompactness / spatialScale, 2) * (spatialDist * spatialDist)
                if combined < bestDistance {
                    bestDistance = combined
                    bestCell = cell
                }
            }
            newLabels[idx] = bestCell
        }
    }
    return newLabels
}

@Suite("Frozen refine equivalence")
struct RefineEquivalenceTests {
    private func compare(width: Int, height: Int, columns: Int, rows: Int, tie: Bool, compactness: Double) {
        let palette = [LabColor(l: 22, a: 3, b: -5), LabColor(l: 75, a: -8, b: 12)]
        let pixels = (0..<(width * height)).map { index in
            tie ? palette[0] : palette[(index / width / 3 + index % width / 4) % 2]
        }
        let image = PixelImage(width: width, height: height, pixels: pixels)
        let weights = (0..<(width * height)).map { index -> Double in
            switch (index / width + index % width) % 4 {
            case 0: return 0.0
            case 1: return 0.03
            case 2: return 1.0
            default: return 100.0
            }
        }
        let importance = ImportanceMap(width: width, height: height, weights: weights)
        let labels = SuperpixelSegmenter.initialLabels(width: width, height: height, columns: columns, rows: rows)
        let stats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: rows,
                                                 importance: importance, labels: labels)
        // A tie between neighboring colors/centers exercises the original Set traversal and strict <.
        let centers = tie ? [CellStats](repeating: CellStats(color: palette[0], centerX: 1.5,
                                                             centerY: 2.5, pixelCount: 1), count: columns * rows) : stats
        let colors = tie ? [LabColor](repeating: palette[0], count: columns * rows) : stats.map(\.color)
        let expected = legacyRefine(image: image, columns: columns, rows: rows,
                                    importance: importance, labels: labels, cellColors: colors,
                                    centers: centers, compactness: compactness)
        let actual = SuperpixelSegmenter.refine(image: image, columns: columns, rows: rows,
                                                importance: importance, labels: labels,
                                                cellColors: colors, centers: centers, compactness: compactness)
        if !tie {
            #expect(actual == expected)
        } else {
            // Separate Set instances can enumerate tied candidates in different orders.
            // Each result must still select one of the original cell's legal neighbors.
            for (index, selected) in actual.enumerated() {
                let own = labels[index], row = own / columns, col = own % columns
                var allowed: Set<Int> = [own]
                if col > 0 { allowed.insert(own - 1) }
                if col + 1 < columns { allowed.insert(own + 1) }
                if row > 0 { allowed.insert(own - columns) }
                if row + 1 < rows { allowed.insert(own + columns) }
                #expect(allowed.contains(selected))
                #expect(allowed.contains(expected[index]))
            }
        }
        #expect(actual.count == width * height)
    }

    @Test("identical candidate distances preserve Set-dependent ties at all grid edges")
    func tiesAndEdges() {
        compare(width: 9, height: 7, columns: 3, rows: 2, tie: true, compactness: 10)
    }

    @Test("non-square image and grid with mixed importance and color boundaries")
    func nonSquareAndImportance() {
        compare(width: 37, height: 23, columns: 7, rows: 4, tie: false, compactness: 13.7)
        compare(width: 23, height: 37, columns: 4, rows: 7, tie: false, compactness: 0.2)
    }

}

/// Manual only: PROFILE_REFINE_BENCHMARKS=1 SWIFT_DETERMINISTIC_HASHING=1
/// swift test --package-path BeadCore -c release --filter RefinePerformanceTests
@Suite("Refine performance (opt-in)", .serialized)
struct RefinePerformanceTests {
    private func measure(_ name: String, _ body: () -> Int) {
        _ = body() // exactly one unmeasured warm-up
        let samples = (0..<5).map { _ -> Double in
            let start = DispatchTime.now().uptimeNanoseconds
            let checksum = body()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            print("REFINE BENCH \(name) checksum=\(checksum) ms=\(String(format: "%.3f", elapsed))")
            return elapsed
        }
        print("REFINE BENCH \(name) median=\(String(format: "%.3f", samples.sorted()[2])) ms")
    }

    @Test("local refine and end-to-end on the same synthetic opaque image and palette")
    func profile() {
        guard ProcessInfo.processInfo.environment["PROFILE_REFINE_BENCHMARKS"] == "1" else { return }
        let side = 288
        let columns = 48
        let palette = MardPalette.standard221
        let context = CGContext(data: nil, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<side {
            let t = CGFloat(y) / CGFloat(side - 1)
            context.setFillColor(red: 0.12 + t * 0.65, green: 0.14 + t * 0.42,
                                 blue: 0.75 - t * 0.53, alpha: 1)
            context.fill(CGRect(x: 0, y: y, width: side, height: 1))
        }
        let source = context.makeImage()!
        let image = PixelImage(cgImage: source)
        let importance = UniformImportanceMapProvider().importanceMap(for: source)
        let labels = SuperpixelSegmenter.initialLabels(width: side, height: side,
                                                       columns: columns, rows: columns)
        let stats = SuperpixelSegmenter.cellStats(image: image, columns: columns, rows: columns,
                                                 importance: importance, labels: labels)
        let colors = stats.map { ColorMatcher.nearest(to: $0.color, in: palette).lab }
        let options = PatternGenerationOptions(columns: columns, rows: columns, palette: palette)
        measure("legacy local 48x48 / 288x288 / 221 colors") {
            legacyRefine(image: image, columns: columns, rows: columns,
                         importance: importance, labels: labels,
                         cellColors: colors, centers: stats).reduce(0, &+)
        }
        measure("local 48x48 / 288x288 / 221 colors") {
            SuperpixelSegmenter.refine(image: image, columns: columns, rows: columns,
                                       importance: importance, labels: labels,
                                       cellColors: colors, centers: stats).reduce(0, &+)
        }
        measure("end-to-end 48x48 / 288x288 / 221 colors") {
            PatternGenerator.generate(cgImage: source, importanceProvider: UniformImportanceMapProvider(),
                                      options: options).colors.count
        }
    }
}
