import CoreGraphics
import Darwin
import Dispatch
import Foundation
import Testing
@testable import BeadCore

@Suite("Source alpha cells")
struct SourceAlphaCellsTests {
    @Test func outsideAndEnclosedHole() {
        var a = [UInt8](repeating: 255, count: 25)
        for y in 0..<5 { for x in 0..<5 where x == 0 || x == 4 || y == 0 || y == 4 { a[y * 5 + x] = 0 } }
        a[2 * 5 + 2] = 0
        let fixed = SourceAlphaCells.classify(alpha: a, width: 5, height: 5, columns: 5, rows: 5)
        #expect(fixed[0] == .outside)
        #expect(fixed[4] == .outside)
        #expect(fixed[2 * 5 + 2] == .hole)
        #expect(fixed[2 * 5 + 1] == nil)
    }

    @Test func diagonalsDoNotConnectButOrthogonalPixelsDo() {
        var a = [UInt8](repeating: 255, count: 9)
        a[0] = 0
        a[4] = 0
        #expect(SourceAlphaCells.classify(alpha: a, width: 3, height: 3, columns: 3, rows: 3)[4] == .hole)
        a[1] = 0
        #expect(SourceAlphaCells.classify(alpha: a, width: 3, height: 3, columns: 3, rows: 3)[4] == .outside)
    }

    @Test func halfCoverageAndAlphaThreshold() {
        #expect(SourceAlphaCells.classify(alpha: [127, 128, 255, 255], width: 2, height: 2, columns: 1, rows: 1) == [nil])
        #expect(SourceAlphaCells.classify(alpha: [127, 128, 0, 255], width: 2, height: 2, columns: 1, rows: 1) == [.outside])
        #expect(SourceAlphaCells.classify(alpha: [0, 0, 0, 0], width: 2, height: 2, columns: 4, rows: 4).allSatisfy { $0 == .outside })
        #expect(SourceAlphaCells.classify(alpha: [255, 255, 255, 255], width: 2, height: 2, columns: 2, rows: 2).allSatisfy { $0 == nil })
    }

    @Test func cgImageAlphaTopRowMapsToFirstGridRow() {
        let space = CGColorSpaceCreateDeviceRGB()
        var rgba: [UInt8] = [0, 0, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255]
        let context = CGContext(data: &rgba, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let fixed = SourceAlphaCells.classify(source: context.makeImage()!, columns: 2, rows: 2)
        #expect(fixed == [.outside, nil, nil, nil])
    }

    // Frozen pre-optimization classify(source:) path: keep decode, fallback and alpha extraction
    // independent of the production source entry point for strict per-cell comparisons.
    private func oldSourceClassification(_ source: CGImage, columns: Int, rows: Int) -> [FixedCell?] {
        let width = source.width
        let height = source.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: &rgba, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else {
            return [FixedCell?](repeating: nil, count: columns * rows)
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        return SourceAlphaCells.classify(alpha: alpha, width: width, height: height, columns: columns, rows: rows)
    }

    private func rgbaImage(width: Int, height: Int, alpha: (Int, Int) -> UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = 28
                bytes[index + 1] = 74
                bytes[index + 2] = 105
                bytes[index + 3] = alpha(x, y)
            }
        }
        let context = CGContext(data: &bytes, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        return context.makeImage()!
    }

    private func rgbImage(width: Int, height: Int) -> CGImage {
        let bytes = [UInt8](repeating: 60, count: width * height * 3)
        let data = Data(bytes)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                       bytesPerRow: width * 3, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: CGDataProvider(data: data as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    @Test func opaqueRGBAndRGBAHaveNoFixedCellsAndMatchOldPath() {
        for image in [rgbImage(width: 11, height: 7), rgbaImage(width: 11, height: 7) { _, _ in 255 }] {
            let actual = SourceAlphaCells.classify(source: image, columns: 4, rows: 3)
            #expect(actual == oldSourceClassification(image, columns: 4, rows: 3))
            #expect(actual.count == 12)
            #expect(actual.allSatisfy { $0 == nil })
        }
    }

    @Test func externalBorderAndInteriorH1HoleMatchOldPath() {
        let image = rgbaImage(width: 9, height: 7) { x, y in
            if x == 0 || x == 8 || y == 0 || y == 6 { return 0 }
            if x == 3 || x == 5 { return (2...4).contains(y) ? 0 : 255 }
            if y == 2 || y == 4 { return (3...5).contains(x) ? 0 : 255 }
            return 255
        }
        let actual = SourceAlphaCells.classify(source: image, columns: 9, rows: 7)
        #expect(actual == oldSourceClassification(image, columns: 9, rows: 7))
        #expect(actual.contains(.outside))
        #expect(actual.contains(.hole))
    }

    @Test func halfTransparentEdgeAnd127Versus128MatchOldPath() {
        let image = rgbaImage(width: 7, height: 5) { x, y in
            if x == 0 { return 128 }
            if x == 6 { return 127 }
            if x == 3 && y == 2 { return 0 }
            return 255
        }
        let actual = SourceAlphaCells.classify(source: image, columns: 7, rows: 5)
        #expect(actual == oldSourceClassification(image, columns: 7, rows: 5))
        #expect(actual[0] == nil)
        #expect(actual[6] == .outside)
        #expect(actual[2 * 7 + 3] == .hole)
    }

    @Test func nonDivisibleDimensionsAndOversizedGridMatchOldPath() {
        let image = rgbaImage(width: 11, height: 7) { x, y in
            if x < 2 && y < 3 { return 0 }
            if x == 6 && y == 3 { return 127 }
            if x == 9 && y == 6 { return 128 }
            return 255
        }
        for (columns, rows) in [(4, 3), (15, 9)] {
            #expect(SourceAlphaCells.classify(source: image, columns: columns, rows: rows)
                    == oldSourceClassification(image, columns: columns, rows: rows))
        }
    }

    @Test func opaqueSourceAlphaDoesNotChangeEndToEndGrid() {
        let image = rgbaImage(width: 32, height: 32) { _, _ in 255 }
        let options = PatternGenerationOptions(columns: 8, rows: 8, iterations: 0)
        let withoutSourceAlpha = PatternGenerator.generate(
            cgImage: image, importanceProvider: UniformImportanceMapProvider(), options: options)
        let withSourceAlpha = PatternGenerator.generate(
            cgImage: image, importanceProvider: UniformImportanceMapProvider(),
            options: options, sourceAlphaImage: image)
        #expect(SourceAlphaCells.classify(source: image, columns: 8, rows: 8)
                == oldSourceClassification(image, columns: 8, rows: 8))
        #expect(withSourceAlpha.colors == withoutSourceAlpha.colors)
        #expect(withSourceAlpha.colors.allSatisfy { $0 != .empty })
    }

    @Test func fastPathDiagnostic() throws {
        guard ProcessInfo.processInfo.environment["CHECK_ALPHA_FAST_PATH"] == "1" else { return }
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/BeadCore/SourceAlphaCells.swift"), encoding: .utf8)
        let sourceMethod = source.components(separatedBy: "public static func classify(source:")[1]
        let guardIndex = try #require(sourceMethod.range(of: "return [FixedCell?](repeating: nil, count: columns * rows)",
                                                        range: sourceMethod.range(of: "context.draw")!.upperBound..<sourceMethod.endIndex)?.lowerBound)
        let extractionIndex = try #require(sourceMethod.range(of: "let alpha = stride(from: 3")?.lowerBound)
        #expect(guardIndex < extractionIndex, "Opaque fast return must precede alpha extraction")
    }

    @Test func optInAlphaBenchmark() {
        guard let sizeText = ProcessInfo.processInfo.environment["ALPHA_BENCH_SIZE"],
              let size = Int(sizeText),
              let mode = ProcessInfo.processInfo.environment["ALPHA_BENCH_MODE"] else { return }
        let source = rgbaImage(width: size, height: size) { _, _ in 255 }
        let columns = min(size, 150)
        let classify: () -> [FixedCell?] = {
            if mode == "old" { return oldSourceClassification(source, columns: columns, rows: columns) }
            return SourceAlphaCells.classify(source: source, columns: columns, rows: columns)
        }
        let warm = classify()
        #expect(warm.count == columns * columns)
        #expect(warm.allSatisfy { $0 == nil })
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let baselineRSS = usage.ru_maxrss
        var times = [Double]()
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = classify()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            #expect(result == warm)
        }
        getrusage(RUSAGE_SELF, &usage)
        print("ALPHA_BENCH mode=\(mode) pixels=\(size)x\(size) samples_ms=\(times.map { String(format: "%.3f", $0) }.joined(separator: ",")) median_ms=\(String(format: "%.3f", times.sorted()[2])) rss_peak_bytes=\(usage.ru_maxrss) rss_after_warmup_bytes=\(baselineRSS)")
    }
}
