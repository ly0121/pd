import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import BeadCore

@Suite("FaithfulGradientRefiner")
struct FaithfulGradientRefinerTests {
    private let a = MardColor(code: "A", hex: "808080")
    private let b = MardColor(code: "B", hex: "838383")
    private let distant = MardColor(code: "D", hex: "999999")
    private let h1 = MardColor(code: "H1", hex: "FDFBFF")

    private func stats(_ colors: [LabColor], contours: [Double] = [], pixelCounts: [Int] = []) -> [CellStats] {
        colors.enumerated().map { index, color in
            CellStats(color: color, centerX: Double(index), centerY: 0,
                      pixelCount: pixelCounts.isEmpty ? 1 : pixelCounts[index],
                      contourFraction: contours.isEmpty ? 0 : contours[index])
        }
    }

    private func row(_ colors: [MardColor]) -> BeadGrid {
        BeadGrid(columns: colors.count, rows: 1, colors: colors)
    }

    private func source(biasedToward color: MardColor, offset: Double = 0) -> [CellStats] {
        stats(Array(repeating: LabColor(l: color.lab.l + offset, a: color.lab.a, b: color.lab.b), count: 5))
    }

    @Test("small source error tradeoff removes an isolated nearest-color B")
    func removesSmallErrorIsland() {
        let input = row([a, a, b, a, a])
        let evidence = source(biasedToward: b)
        let output = FaithfulGradientRefiner.refine(input, sourceStats: evidence, palette: [a, b], protected: [])
        #expect(output.colors == [a, a, a, a, a])
        #expect(evidence[2].color.distance(to: a.lab) > evidence[2].color.distance(to: b.lab))
        #expect(evidence[2].color.distance(to: a.lab) - evidence[2].color.distance(to: b.lab) <= 2)
    }

    @Test("source error increase above two leaves an island")
    func rejectsLargerError() {
        let input = row([a, a, distant, a, a])
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: source(biasedToward: distant), palette: [a, distant], protected: []) == input)
    }

    @Test("bright chromatic source edge remains even if a neighbor color is eligible")
    func protectsChromaticEdge() {
        let input = row([a, a, b, a, a])
        var evidence = source(biasedToward: b)
        evidence[1].color = LabColor(l: b.lab.l, a: b.lab.a + 20, b: b.lab.b)
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: evidence, palette: [a, b], protected: []) == input)
    }

    @Test("interleaved real source texture is not flattened")
    func protectsTexture() {
        let input = row([a, a, b, a, a])
        var evidence = source(biasedToward: b)
        evidence[3].color = LabColor(l: b.lab.l + 12, a: b.lab.a, b: b.lab.b)
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: evidence, palette: [a, b], protected: []) == input)
    }

    @Test("contour evidence on the center or neighbors prevents replacement")
    func protectsContours() {
        let input = row([a, a, b, a, a])
        for index in [1, 2, 3] {
            var evidence = source(biasedToward: b)
            evidence[index].contourFraction = 0.18
            #expect(FaithfulGradientRefiner.refine(input, sourceStats: evidence, palette: [a, b], protected: []) == input)
        }
    }

    @Test("explicit fixed cell and its orthogonal neighbors cannot change")
    func protectsFixedNeighborhood() {
        let input = row([a, a, b, a, a])
        for index in [1, 2, 3] {
            #expect(FaithfulGradientRefiner.refine(input, sourceStats: source(biasedToward: b), palette: [a, b], protected: [index]) == input)
        }
    }

    @Test("H1 itself and its orthogonal neighbors stay fixed even without an explicit mask")
    func protectsH1Neighborhood() {
        let input = row([a, h1, b, a, a])
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: source(biasedToward: b), palette: [a, b, h1], protected: []) == input)
        let island = row([a, a, h1, a, a])
        #expect(FaithfulGradientRefiner.refine(island, sourceStats: source(biasedToward: b), palette: [a, h1], protected: []) == island)
    }

    @Test("EMPTY is never filled or used to complete an isolated neighborhood")
    func preservesEmpty() {
        let input = row([a, .empty, b, a, a])
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: source(biasedToward: b), palette: [a, b, .empty], protected: []) == input)
        let emptyIsland = row([a, a, .empty, a, a])
        #expect(FaithfulGradientRefiner.refine(emptyIsland, sourceStats: source(biasedToward: b), palette: [a, b, .empty], protected: []) == emptyIsland)
    }

    @Test("neighbor replacement absent from current palette is rejected")
    func rejectsExcludedPaletteColor() {
        let input = row([a, a, b, a, a])
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: source(biasedToward: b), palette: [b], protected: []) == input)
    }

    @Test("missing, mismatched, or empty-pixel source evidence does not change grid")
    func requiresValidEvidence() {
        let input = row([a, a, b, a, a])
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: [], palette: [a, b], protected: []) == input)
        for index in [1, 2, 3] {
            var evidence = source(biasedToward: b)
            evidence[index].pixelCount = 0
            #expect(FaithfulGradientRefiner.refine(input, sourceStats: evidence, palette: [a, b], protected: []) == input)
        }
    }

    @Test("one-percent cap chooses earliest candidate using the original grid")
    func capsRowMajorAndAvoidsCascades() {
        var colors = [MardColor](repeating: a, count: 100)
        colors[10] = b
        colors[30] = b
        let input = row(colors)
        let output = FaithfulGradientRefiner.refine(input, sourceStats: stats(Array(repeating: b.lab, count: 100)), palette: [a, b], protected: [])
        #expect(output.colors[10] == a)
        #expect(output.colors[30] == b)
        #expect(zip(input.colors, output.colors).filter { $0 != $1 }.count == 1)
    }

    @Test("H1 orthogonal vertical neighbor is protected, while a distant island can change")
    func protectsVerticalH1Neighbor() {
        var colors = [MardColor](repeating: a, count: 25)
        colors[7] = b
        colors[2] = h1
        colors[17] = b
        let input = BeadGrid(columns: 5, rows: 5, colors: colors)
        let result = FaithfulGradientRefiner.refineWithChanges(
            input, sourceStats: stats(Array(repeating: b.lab, count: 25)), palette: [a, b, h1], protected: [])
        #expect(result.grid.colors[7] == b)
        #expect(result.grid.colors[17] == a)
        #expect(result.grid.colors[2] == h1)
        #expect(result.changes.map(\.index) == [17])
        #expect(result.changes[0].oldColor == b)
        #expect(result.changes[0].newColor == a)
        #expect(result.changes[0].errorIncrease > 0)
        #expect(result.changes[0].errorIncrease <= 2)
        #expect(result.changes[0].neighborJumpReduction > 0)
        #expect(!result.changes[0].reason.isEmpty)
    }

    @Test("simultaneous decisions cannot use an earlier replacement as an old neighbor")
    func readsOriginalGrid() {
        let input = row([a, a, b, b, a, a])
        let result = FaithfulGradientRefiner.refine(input, sourceStats: stats(Array(repeating: b.lab, count: 6)), palette: [a, b], protected: [])
        #expect(result == input)
    }

    @Test("small nonempty grid allows one edit despite floor of one percent")
    func smallGridAllowsOne() {
        let input = row([a, a, b, a, a])
        #expect(FaithfulGradientRefiner.refine(input, sourceStats: source(biasedToward: b), palette: [a, b], protected: []).colors[2] == a)
    }
}

#if canImport(AppKit)
@Suite("Generated gradient comparison")
struct GeneratedGradientComparisonTests {
    @Test("synthetic fixtures retain production baseline and respect experimental edit constraints")
    func compareGeneratedFixtures() throws {
        let reports = try GradientComparisonHarness.run()
        #expect(reports.count == 3)
    }
}

private enum GradientComparisonHarness {
    private static let root = URL(fileURLWithPath: "/Users/jinyuanhui/pd/docs/superpowers/benchmarks", isDirectory: true)
    private static let columns = 40
    private static let rows = 32
    private static let scale = 6
    private static let width = columns * scale
    private static let height = rows * scale
    private static let palette = MardPalette.standard221
    private static let dark = palette.first { $0.code == "H7" }!
    private static let h1 = palette.first { $0.code == "H1" }!

    struct Report { let name: String; let changes: Int }

    static func run() throws -> [Report] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try ["smooth", "contour", "texture"].map { name in
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
            if ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] == "1" {
                let production = PatternGenerator.generate(cgImage: source,
                    importanceProvider: UniformImportanceMapProvider(), options: options, sourceAlphaImage: source)
                #expect(baseline == production, "test pipeline must match default generator: \(name)")
            }
            let result = FaithfulGradientRefiner.refineWithChanges(baseline,
                sourceStats: optimized.cellStats, palette: palette, protected: protected)
            let changes = result.changes
            let count = baseline.colors.indices.filter { baseline.colors[$0] != .empty && baseline.colors[$0].code != "H1" && !protected.contains($0) }.count
            #expect(changes.count <= max(1, count / 100))
            #expect(zip(baseline.colors, result.grid.colors).filter { $0 != $1 }.count == changes.count)
            for change in changes {
                let i = change.index
                let x = i % columns, y = i / columns
                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].filter {
                    $0.0 >= 0 && $0.0 < columns && $0.1 >= 0 && $0.1 < rows
                }.map { $0.1 * columns + $0.0 }
                #expect(palette.contains(change.newColor) && change.newColor != .empty && change.newColor.code != "H1")
                #expect(change.errorIncrease <= 2.0 && change.neighborJumpReduction > 0)
                #expect(!protected.contains(i) && neighbors.allSatisfy { !protected.contains($0) })
                #expect(optimized.cellStats[i].contourFraction < 0.18)
                #expect(neighbors.allSatisfy { optimized.cellStats[$0].contourFraction < 0.18 })
                let participants = [i] + neighbors
                #expect(participants.allSatisfy { a in participants.allSatisfy { b in
                    optimized.cellStats[a].color.distance(to: optimized.cellStats[b].color) <= 4.0
                } })
                print(String(format: "GRADIENT_EDIT %@ (%d,%d) %@ -> %@ old=%.4f new=%.4f delta=%.4f neighborJumpReduction=%.4f",
                    name, x, y, change.oldColor.code, change.newColor.code,
                    optimized.cellStats[i].color.distance(to: change.oldColor.lab),
                    optimized.cellStats[i].color.distance(to: change.newColor.lab),
                    change.errorIncrease, change.neighborJumpReduction))
            }
            let eligible = baseline.colors.indices.filter { i in
                let x = i % columns, y = i / columns
                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].filter {
                    $0.0 >= 0 && $0.0 < columns && $0.1 >= 0 && $0.1 < rows
                }.map { $0.1 * columns + $0.0 }
                guard neighbors.count >= 2, baseline.colors[i] != .empty, baseline.colors[i].code != "H1",
                      !protected.contains(i), neighbors.allSatisfy({ !protected.contains($0) && baseline.colors[$0] != .empty && baseline.colors[$0].code != "H1" }),
                      let first = neighbors.first else { return false }
                return baseline.colors[i] != baseline.colors[first] && neighbors.allSatisfy { baseline.colors[$0] == baseline.colors[first] }
            }
            let feasible = eligible.filter { i in
                let x = i % columns, y = i / columns
                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].filter {
                    $0.0 >= 0 && $0.0 < columns && $0.1 >= 0 && $0.1 < rows
                }.map { $0.1 * columns + $0.0 }
                let group = [i] + neighbors, stats = optimized.cellStats
                guard group.allSatisfy({ stats[$0].pixelCount > 0 && stats[$0].contourFraction < 0.18 }),
                      group.allSatisfy({ a in group.allSatisfy { b in stats[a].color.distance(to: stats[b].color) <= 4 } }),
                      let first = neighbors.first else { return false }
                let candidate = baseline.colors[first]
                return palette.contains(candidate) && stats[i].color.distance(to: candidate.lab) - stats[i].color.distance(to: baseline.colors[i].lab) <= 2
            }
            let valid = baseline.colors.indices.filter { baseline.colors[$0] != .empty && baseline.colors[$0].code != "H1" && optimized.cellStats[$0].pixelCount > 0 }
            let old = valid.map { optimized.cellStats[$0].color.distance(to: baseline.colors[$0].lab) }
            let new = valid.map { optimized.cellStats[$0].color.distance(to: result.grid.colors[$0].lab) }
            func stats(_ errors: [Double]) -> String {
                let sorted = errors.sorted()
                return String(format: "mean=%.4f p95=%.4f p99=%.4f", errors.reduce(0,+)/Double(errors.count),
                    sorted[Int(Double(sorted.count - 1) * 0.95)], sorted[Int(Double(sorted.count - 1) * 0.99)])
            }
            let bands = baseline.colors.indices.filter { i in
                let x = i % columns, y = i / columns
                return (x + 1 < columns && baseline.colors[i] != baseline.colors[i + 1] && baseline.colors[i] != .empty && baseline.colors[i + 1] != .empty
                    ? [i, i + 1] : []) + (y + 1 < rows && baseline.colors[i] != baseline.colors[i + columns] && baseline.colors[i] != .empty && baseline.colors[i + columns] != .empty
                    ? [i, i + columns] : []) != []
            }.count
            let edges: (BeadGrid) -> Int = { grid in
                (0..<(columns * rows)).reduce(0) { total, i in
                    let x = i % columns, y = i / columns
                    return total + (x + 1 < columns && grid.colors[i] != .empty && grid.colors[i + 1] != .empty && grid.colors[i] != grid.colors[i + 1] ? 1 : 0)
                                 + (y + 1 < rows && grid.colors[i] != .empty && grid.colors[i + columns] != .empty && grid.colors[i] != grid.colors[i + columns] ? 1 : 0)
                }
            }
            print("GRADIENT_REPORT \(name) cells=\(valid.count) fixed=\(protected.count) isolated=\(eligible.count) feasible=\(feasible.count) actual=\(changes.count) hardEdges=\(edges(baseline))->\(edges(result.grid)) hardBandCells=\(bands) old{\(stats(old))} new{\(stats(new))}")
            let strip = makeStrip(source: source, baseline: baseline, candidate: result.grid)
            let png = NSBitmapImageRep(cgImage: strip).representation(using: .png, properties: [:])!
            let url = root.appendingPathComponent("2026-11-09-gradient-\(name)-comparison.png")
            try png.write(to: url)
            print("GRADIENT_IMAGE \(url.path)")
            return Report(name: name, changes: changes.count)
        }
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
