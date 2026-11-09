import CoreGraphics
import Dispatch
import Foundation
import Testing
@testable import BeadCore

/// Manual benchmark: PROFILE_GENERATION_BENCHMARKS=1 swift test --package-path BeadCore --filter GenerationBenchmarkTests
/// Set PROFILE_GENERATION_STAGES=1 to include independent per-stage diagnostic runs.
@Suite("Generation benchmarks", .serialized)
struct GenerationBenchmarkTests {
    private struct Case {
        let columns: Int
        let pixels: Int
        let palette: [MardColor]
        var name: String { "\(columns)x\(columns)/\(pixels)x\(pixels)/\(palette.count) colors" }
        var options: PatternGenerationOptions {
            PatternGenerationOptions(columns: columns, rows: columns, palette: palette)
        }
    }

    private let cases = [
        Case(columns: 48, pixels: 288, palette: MardPalette.standard221),
        Case(columns: 100, pixels: 400, palette: MardPalette.allColors),
        Case(columns: 150, pixels: 900, palette: MardPalette.standard221),
    ]

    private func image(side: Int) -> CGImage {
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
        for row in 0..<4 {
            for col in 0..<4 where (row + col) % 2 == 0 {
                context.setFillColor(red: CGFloat(col + 1) / 6,
                                     green: CGFloat(row + 1) / 5, blue: 0.19, alpha: 1)
                context.fill(CGRect(x: col * side / 4, y: row * side / 4,
                                    width: side / 9, height: side / 9))
            }
        }
        return context.makeImage()!
    }

    private func milliseconds<T>(_ body: () -> T) -> (T, Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = body()
        return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    private func measure(_ name: String, _ body: () -> Void) {
        body() // Warm-up outside the five measured trials.
        let samples = (0..<5).map { _ in milliseconds(body).1 }
        let median = samples.sorted()[2]
        let values = samples.map { String(format: "%.2f", $0) }.joined(separator: ", ")
        print("BENCH \(name): [\(values)] ms median \(String(format: "%.2f", median)) ms")
    }

    @Test("end-to-end warm-up and five timed trials per size")
    func endToEnd() {
        guard ProcessInfo.processInfo.environment["PROFILE_GENERATION_BENCHMARKS"] == "1" else { return }
        for item in cases {
            let source = image(side: item.pixels)
            measure("total \(item.name) uniform") {
                let grid = PatternGenerator.generate(cgImage: source,
                    importanceProvider: UniformImportanceMapProvider(), options: item.options)
                #expect(grid.colors.count == item.columns * item.columns)
            }
        }
    }

    @Test("optional independent stage profiles, five timed trials each")
    func stageProfiles() {
        guard ProcessInfo.processInfo.environment["PROFILE_GENERATION_STAGES"] == "1" else { return }
        for item in cases {
            let source = image(side: item.pixels)
            let pixelImage = PixelImage(cgImage: source)
            let uniform = UniformImportanceMapProvider().importanceMap(for: source)
            let contours = ContourDetector.detect(pixelImage)
            let optimized = PaletteOptimizer.optimize(
                image: pixelImage, columns: item.columns, rows: item.columns,
                importance: uniform, palette: item.palette, contourWeights: contours)
            let grid = PaletteOptimizer.makeGrid(from: optimized)
            let cleaned = NoiseCleaner.clean(grid, maxIsolatedCount: item.options.maxIsolatedCount)
            measure("PixelImage \(item.name)") { _ = PixelImage(cgImage: source) }
            measure("importance uniform \(item.name)") {
                _ = UniformImportanceMapProvider().importanceMap(for: source)
            }
            measure("importance Vision \(item.name)") {
                _ = VisionSaliencyImportanceMapProvider().importanceMap(for: source)
            }
            measure("ContourDetector \(item.name)") { _ = ContourDetector.detect(pixelImage) }
            measure("PaletteOptimizer \(item.name)") {
                _ = PaletteOptimizer.optimize(image: pixelImage, columns: item.columns, rows: item.columns,
                                              importance: uniform, palette: item.palette,
                                              contourWeights: contours)
            }
            measure("NoiseCleaner \(item.name)") {
                _ = NoiseCleaner.clean(grid, maxIsolatedCount: item.options.maxIsolatedCount)
            }
            measure("GradientOrderEnforcer \(item.name)") {
                _ = GradientOrderEnforcer.enforce(cleaned, sourceStats: optimized.cellStats,
                                                   palette: item.palette)
            }
            measure("SourceAlphaCells \(item.name)") {
                _ = SourceAlphaCells.classify(source: source, columns: item.columns, rows: item.columns)
            }
            // Independent samples for internals, not additive to the optimizer's wall time.
            let labels = SuperpixelSegmenter.initialLabels(width: item.pixels, height: item.pixels,
                                                            columns: item.columns, rows: item.columns)
            let stats = SuperpixelSegmenter.cellStats(image: pixelImage, columns: item.columns,
                                                      rows: item.columns, importance: uniform, labels: labels,
                                                      contourWeights: contours)
            let colors = stats.map { ColorMatcher.nearest(to: $0.color, in: item.palette) }
            measure("optimizer initialLabels \(item.name)") {
                _ = SuperpixelSegmenter.initialLabels(width: item.pixels, height: item.pixels,
                                                       columns: item.columns, rows: item.columns)
            }
            measure("optimizer cellStats \(item.name)") {
                _ = SuperpixelSegmenter.cellStats(image: pixelImage, columns: item.columns,
                    rows: item.columns, importance: uniform, labels: labels, contourWeights: contours)
            }
            measure("optimizer nearest legacy \(item.name)") {
                _ = stats.map { ColorMatcher.nearest(to: $0.color, in: item.palette) }
            }
            measure("optimizer refine \(item.name)") {
                _ = SuperpixelSegmenter.refine(image: pixelImage, columns: item.columns,
                    rows: item.columns, importance: uniform, labels: labels,
                    cellColors: colors.map(\.lab), centers: stats)
            }
        }
    }
}
