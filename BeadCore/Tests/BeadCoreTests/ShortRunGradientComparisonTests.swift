import Testing
#if canImport(AppKit)
import AppKit
@testable import BeadCore

@Suite("Short-run gradient comparison")
struct ShortRunGradientComparisonTests {
    @Test("real generated grids are compared against the opt-in experiment")
    func compareGeneratedFixtures() throws {
        try ShortRunComparisonHarness.run()
    }
}

/// The fixture pixels, baseline stages, and strip geometry match GeneratedGradientComparisonTests.
/// Kept separate so rerunning this experiment never overwrites the first comparison.
private enum ShortRunComparisonHarness {
    private static let root = URL(fileURLWithPath: "/Users/jinyuanhui/pd/docs/superpowers/benchmarks", isDirectory: true)
    private static let columns = 40, rows = 32, scale = 6
    private static let width = columns * scale, height = rows * scale
    private static let palette = MardPalette.standard221
    private static let h1 = palette.first { $0.code == "H1" }!

    static func run() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["smooth", "contour", "texture"] {
            let source = makeImage(name: name)
            let image = PixelImage(cgImage: source)
            let importance = ImportanceMap.uniform(width: width, height: height)
            let options = PatternGenerationOptions(columns: columns, rows: rows, palette: palette)
            let optimized = PaletteOptimizer.optimize(image: image, columns: columns, rows: rows,
                importance: importance, palette: palette, iterations: options.iterations,
                compactness: options.compactness, contourWeights: ContourDetector.detect(image))
            let cleaned = NoiseCleaner.clean(PaletteOptimizer.makeGrid(from: optimized),
                maxIsolatedCount: options.maxIsolatedCount)
            var baseline = GradientOrderEnforcer.enforce(cleaned, sourceStats: optimized.cellStats, palette: palette)
            let fixed = SourceAlphaCells.classify(source: source, columns: columns, rows: rows)
            var protected = Set<Int>()
            for (index, kind) in fixed.enumerated() {
                switch kind {
                case .outside: baseline.colors[index] = .empty; protected.insert(index)
                case .hole: baseline.colors[index] = h1; protected.insert(index)
                case nil: break
                }
            }
            // A second optimizer run can make an unseeded Set-tie comparison meaningless.
            // Run this assertion only when the caller explicitly seeds Swift hashing.
            if ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] == "1" {
                let production = PatternGenerator.generate(cgImage: source,
                    importanceProvider: UniformImportanceMapProvider(), options: options, sourceAlphaImage: source)
                #expect(baseline == production, "baseline must match default generator: \(name)")
            }
            let result = ShortRunGradientExperiment.propose(baseline,
                sourceStats: optimized.cellStats, palette: palette, protected: protected, sourceImage: image)
            let candidate = result.grid
            let eligibleCells = baseline.colors.indices.filter { !protected.contains($0) && baseline.colors[$0] != .empty && baseline.colors[$0].code != "H1" }
            let changed = baseline.colors.indices.filter { baseline.colors[$0] != candidate.colors[$0] }
            #expect(changed.count == result.changes.count)
            #expect(Set(changed) == Set(result.changes.map(\.index)))
            #expect(changed.count <= max(1, eligibleCells.count / 100))
            let fixedAndNeighbors = protected.reduce(into: protected) { set, index in
                set.formUnion(neighbors(index))
            }.union(baseline.colors.indices.filter { baseline.colors[$0] == .empty || baseline.colors[$0].code == "H1" })
            let fixedDiffs = fixedAndNeighbors.filter { baseline.colors[$0] != candidate.colors[$0] }.count
            #expect(fixedDiffs == 0)
            #expect(baseline.colors.indices.filter { baseline.colors[$0] == .empty || baseline.colors[$0].code == "H1" }
                .allSatisfy { baseline.colors[$0] == candidate.colors[$0] })
            for change in result.changes {
                let i = change.index
                #expect(baseline.colors[i].code == change.oldCode && candidate.colors[i].code == change.newCode)
                #expect(palette.contains(candidate.colors[i]))
                #expect(change.newError - change.oldError <= 2.0 + 1e-9)
                #expect(!fixedAndNeighbors.contains(i))
                #expect(optimized.cellStats[i].pixelCount > 0)
                print(String(format: "SHORT_RUN_EDIT %@ (%d,%d) %@ -> %@ oldDeltaE=%.4f newDeltaE=%.4f delta=%.4f reason=%@",
                    name, i % columns, i / columns, change.oldCode, change.newCode,
                    change.oldError, change.newError, change.newError - change.oldError, change.reason))
            }
            let valid = baseline.colors.indices.filter { baseline.colors[$0] != .empty && baseline.colors[$0].code != "H1" && optimized.cellStats[$0].pixelCount > 0 }
            let old = valid.map { optimized.cellStats[$0].color.distance(to: baseline.colors[$0].lab) }
            let new = valid.map { optimized.cellStats[$0].color.distance(to: candidate.colors[$0].lab) }
            let oldEdges = edges(baseline), newEdges = edges(candidate)
            let rawRough = baseline.colors.indices.filter { !rawRectangleIsSmooth($0, source: image) }.count
            let emptyCount = baseline.colors.filter { $0 == .empty }.count
            let h1Count = baseline.colors.filter { $0.code == "H1" }.count
            print("SHORT_RUN_REPORT \(name) cells=\(columns * rows) eligibleCells=\(eligibleCells.count) eligibleSegments=\(result.eligibleSegments) feasibleCandidates=\(result.feasibleCandidates) actual=\(changed.count) changedPercent=\(String(format: "%.4f", 100 * Double(changed.count) / Double(eligibleCells.count))) protected=\(protected.count) empty=\(emptyCount) H1=\(h1Count) fixedNeighborDiffs=\(fixedDiffs) rawRoughRectangles=\(rawRough) hardEdges=\(oldEdges.count)->\(newEdges.count) oldHistogram=\(histogram(oldEdges)) newHistogram=\(histogram(newEdges)) oldError{\(errorStats(old))} newError{\(errorStats(new))}")
            let strip = makeStrip(source: source, baseline: baseline, candidate: candidate)
            #expect(strip.width == width * 3 + 24 && strip.height == height)
            let png = try #require(NSBitmapImageRep(cgImage: strip).representation(using: .png, properties: [:]))
            let url = root.appendingPathComponent("2026-11-09-gradient-short-run-\(name)-comparison.png")
            try png.write(to: url)
            print("SHORT_RUN_IMAGE \(url.path)")
        }
    }

    private static func neighbors(_ index: Int) -> [Int] {
        let x = index % columns, y = index / columns
        return [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            .filter { $0.0 >= 0 && $0.0 < columns && $0.1 >= 0 && $0.1 < rows }
            .map { $0.1 * columns + $0.0 }
    }

    private static func edges(_ grid: BeadGrid) -> [Double] {
        var result: [Double] = []
        for i in grid.colors.indices where grid.colors[i] != .empty {
            for next in [i % columns + 1 < columns ? i + 1 : -1, i / columns + 1 < rows ? i + columns : -1]
                where next >= 0 && grid.colors[next] != .empty && grid.colors[i] != grid.colors[next] {
                result.append(grid.colors[i].lab.distance(to: grid.colors[next].lab))
            }
        }
        return result
    }

    private static func histogram(_ jumps: [Double]) -> String {
        let ranges = [jumps.filter { $0 <= 2 }.count, jumps.filter { $0 > 2 && $0 <= 5 }.count,
                      jumps.filter { $0 > 5 && $0 <= 10 }.count, jumps.filter { $0 > 10 }.count]
        return ranges.map(String.init).joined(separator: "/")
    }

    private static func errorStats(_ errors: [Double]) -> String {
        guard !errors.isEmpty else { return "n=0" }
        let sorted = errors.sorted()
        return String(format: "n=%d mean=%.4f p95=%.4f p99=%.4f", errors.count,
            errors.reduce(0, +) / Double(errors.count),
            sorted[Int(Double(sorted.count - 1) * 0.95)], sorted[Int(Double(sorted.count - 1) * 0.99)])
    }

    // Same 6-ΔE76 fixed-rectangle check as the experiment, independently counted
    // to expose local raw-pixel texture that SLIC means alone cannot describe.
    private static func rawRectangleIsSmooth(_ index: Int, source: PixelImage) -> Bool {
        let col = index % columns, row = index / columns
        let x0 = (col * width + columns - 1) / columns, x1 = ((col + 1) * width + columns - 1) / columns
        let y0 = (row * height + rows - 1) / rows, y1 = ((row + 1) * height + rows - 1) / rows
        var pixels: [LabColor] = []
        for y in y0..<y1 { for x in x0..<x1 {
            let pixel = source.pixel(x: x, y: y)
            guard pixels.allSatisfy({ $0.distance(to: pixel) <= 6 }) else { return false }
            pixels.append(pixel)
        } }
        return true
    }

    private static func makeImage(name: String) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let index = (y * width + x) * 4
            let t = Double(x) / Double(width - 1)
            let shade = UInt8((75 + 150 * t).rounded())
            pixels[index] = shade; pixels[index + 1] = shade; pixels[index + 2] = shade
            if name == "contour" && (abs(y - (height / 3 + x / 8)) <= 2 || (x >= 150 && x <= 153 && y > 70 && y < 145)) {
                pixels[index] = 32; pixels[index + 1] = 28; pixels[index + 2] = 50
            }
            if name == "contour" && x >= 148 && x < 161 && y >= 68 && y < 145 {
                pixels[index] = 19; pixels[index + 1] = 75; pixels[index + 2] = 180
            }
            if name == "texture" {
                let stripe = (x / 14) % 4 == 1 && y >= 24 && y < 158
                let spot = (x - 153) * (x - 153) + (y - 95) * (y - 95) < 17 * 17
                    || (x - 90) * (x - 90) + (y - 143) * (y - 143) < 10 * 10
                if stripe || spot {
                    pixels[index] = 57; pixels[index + 1] = 92; pixels[index + 2] = 172
                }
            }
            if name == "contour" && ((x < 12 || y < 12 || x >= width - 12 || y >= height - 12)
                || (x >= 110 && x < 128 && y >= 104 && y < 122)) { pixels[index + 3] = 0 }
        } }
        let context = CGContext(data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        return context.makeImage()!
    }

    private static func makeStrip(source: CGImage, baseline: BeadGrid, candidate: BeadGrid) -> CGImage {
        let gap = 12
        let context = CGContext(data: nil, width: width * 3 + gap * 2, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width * 3 + gap * 2, height: height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        for (n, grid) in [baseline, candidate].enumerated() {
            for (index, color) in grid.colors.enumerated() where color != .empty {
                context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
                context.fill(CGRect(x: width * (n + 1) + gap * (n + 1) + index % columns * scale,
                    y: height - (index / columns + 1) * scale, width: scale, height: scale))
            }
        }
        return context.makeImage()!
    }
}
#endif
