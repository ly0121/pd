import CoreGraphics
import Foundation
import Testing
@testable import BeadCore

@Suite("Generation golden grids")
struct GenerationEquivalenceTests {
    private static func gradient() -> PixelImage {
        let side = 96
        let pixels = (0..<side * side).map { index -> LabColor in
            let x = index % side
            let y = index / side
            let contour = (x == 23 || y == 51) && x > 8 && y > 8
            return contour ? LabColor(red: 0.06, green: 0.05, blue: 0.09) :
                LabColor(red: Double(x) / 120 + 0.12, green: Double(y) / 130 + 0.11,
                         blue: Double(x + y) / 260 + 0.17)
        }
        return PixelImage(width: side, height: side, pixels: pixels)
    }

    private static func checkerboard() -> PixelImage {
        let side = 128
        let h2 = MardPalette.allColors.first { $0.code == "H2" }!.lab
        let h4 = MardPalette.allColors.first { $0.code == "H4" }!.lab
        let pixels = (0..<side * side).map { index in
            ((index % side / 4 + index / side / 4) % 2 == 0) ? h2 : h4
        }
        return PixelImage(width: side, height: side, pixels: pixels)
    }

    private static func alphaImage() -> CGImage {
        let side = 48
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let index = (y * side + x) * 4
                rgba[index] = UInt8(55 + x * 3)
                rgba[index + 1] = UInt8(85 + y * 2)
                rgba[index + 2] = 95
                rgba[index + 3] = (x < 8 || x >= 40 || y < 8 || y >= 40 ||
                                   (x >= 20 && x < 28 && y >= 20 && y < 28)) ? 0 : 255
            }
        }
        let context = CGContext(data: &rgba, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                    CGBitmapInfo.byteOrder32Big.rawValue)!
        return context.makeImage()!
    }

    @Test("24x24 RGB gradient and dark contour, standard palette")
    func gradientStandard() {
        let image = Self.gradient()
        let options = PatternGenerationOptions(columns: 24, rows: 24, palette: MardPalette.standard221, iterations: 0)
        check({ PatternGenerator.generate(image: image, importance: .uniform(width: 96, height: 96), options: options) },
              expected: Self.gradientStandardCodes)
    }

    @Test("24x24 RGB gradient and dark contour, sampled palette")
    func gradientSampled() {
        let image = Self.gradient()
        let palette = PaletteSampler.sample(count: 12, from: MardPalette.standard221)
        #expect(palette.count == 12)
        let options = PatternGenerationOptions(columns: 24, rows: 24, palette: palette, iterations: 0)
        check({ PatternGenerator.generate(image: image, importance: .uniform(width: 96, height: 96), options: options) },
              expected: Self.gradientSampledCodes)
    }

    @Test("32x32 H2/H4 checkerboard, complete palette")
    func checkerAllColors() {
        let image = Self.checkerboard()
        let options = PatternGenerationOptions(columns: 32, rows: 32, palette: MardPalette.allColors)
        check({ PatternGenerator.generate(image: image, importance: .uniform(width: 128, height: 128), options: options) },
              expected: Self.checkerCodes)
    }

    @Test("12x12 alpha outside and enclosed H1 hole")
    func alphaAndHole() {
        let source = Self.alphaImage()
        let h1 = MardPalette.allColors.first { $0.code == "H1" }!
        let h7 = MardPalette.allColors.first { $0.code == "H7" }!
        let options = PatternGenerationOptions(columns: 12, rows: 12, palette: [h1, h7])
        check({ PatternGenerator.generate(cgImage: source, importanceProvider: UniformImportanceMapProvider(),
                                          options: options, sourceAlphaImage: source) },
              expected: Self.alphaCodes)
    }

    @Test("12x12 alpha cells with H1 as the only candidate")
    func alphaH1Only() {
        let source = Self.alphaImage()
        let h1 = MardPalette.allColors.first { $0.code == "H1" }!
        let options = PatternGenerationOptions(columns: 12, rows: 12, palette: [h1])
        check({ PatternGenerator.generate(cgImage: source, importanceProvider: UniformImportanceMapProvider(),
                                          options: options, sourceAlphaImage: source) },
              expected: Self.alphaH1OnlyCodes)
    }

    @Test("24x24 gradient with dark contour and default iterative refinement, H1-only palette")
    func gradientIterativeH1Only() {
        let image = Self.gradient()
        let h1 = MardPalette.allColors.first { $0.code == "H1" }!
        let options = PatternGenerationOptions(columns: 24, rows: 24, palette: [h1])
        #expect(options.iterations > 0)
        check({ PatternGenerator.generate(image: image, importance: .uniform(width: 96, height: 96),
                                          options: options) }, expected: Self.gradientIterativeH1Codes)
    }

    @Test("24x24 varied RGB image through full CGImage path at default refinement")
    func rgbIterativeCGImage() {
        let side = 96
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let palette = ["A14", "B8", "C7", "D15"].map { code in
            MardPalette.standard221.first { $0.code == code }!
        }
        for row in 0..<24 {
            for col in 0..<24 {
                let color = palette[(col / 6 + row / 6) % palette.count]
                context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
                context.fill(CGRect(x: col * 4, y: row * 4, width: 4, height: 4))
            }
        }
        let source = context.makeImage()!
        let options = PatternGenerationOptions(columns: 24, rows: 24, palette: palette)
        #expect(options.iterations > 0)
        check({ PatternGenerator.generate(cgImage: source, importanceProvider: UniformImportanceMapProvider(),
                                          options: options) }, expected: Self.rgbIterativeCodes)
    }

    @Test("default-iteration broad-palette gradient with controlled Set hashing")
    func seededIterativeGradient() {
        guard ProcessInfo.processInfo.environment["SWIFT_DETERMINISTIC_HASHING"] == "1" else { return }
        let image = Self.gradient()
        let options = PatternGenerationOptions(columns: 24, rows: 24, palette: MardPalette.standard221)
        check({ PatternGenerator.generate(image: image, importance: .uniform(width: 96, height: 96),
                                          options: options) }, expected: Self.seededIterativeGradientCodes)
    }

    private func check(_ generate: () -> BeadGrid, expected: String) {
        let expectedCodes = expected.split(whereSeparator: \.isWhitespace).map(String.init)
        let first = generate().colors.map(\.code)
        #expect(expectedCodes.count == first.count)
        #expect(first == expectedCodes)
        for _ in 0..<2 {
            #expect(generate().colors.map(\.code) == first)
        }
    }

    // Captured from the unoptimized generator on this branch; row-major codes including EMPTY.
    private static let seededIterativeGradientCodes = """
H7 H5 H5 H5 H5 H5 H5 G8 G8 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G8 G8 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G17 G8 E22 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
H5 H5 H5 H5 H5 H5 H5 H4 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
B12 B12 H5 H5 H5 H5 H5 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 H5 H5 H5 H5 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 B12 H5 H5 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 B12 B12 H7 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 H7 H7 H4 H7 H7 H7 H7 H7 H7 H7 H7 H7 H7 G17 H7 H7 H7 H7 H7 E7 H7
B12 B12 B12 B12 B12 H7 H4 H4 H4 H4 H4 H4 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E3 E4
B12 B12 B12 B12 B12 B12 H4 H4 H4 H4 H4 H4 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 B12 B12 B12 H4 H4 H4 H4 H4 H4 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E3 E3
B8 B12 B12 B12 B12 B12 C11 H4 H4 H4 H4 H4 H4 H4 H4 E20 D19 E22 E22 E22 E22 E22 E3 E3
B8 B8 B8 B12 B12 B12 B6 C11 C25 C25 H4 H4 H4 H4 H4 E20 E20 D19 D19 D19 E22 E22 E2 E3
B8 B8 B8 B6 B6 H7 B6 C11 C25 C25 C25 C25 H4 H4 H4 E20 E20 E20 D19 D19 D19 D19 E2 E2
B8 B8 B6 B6 B6 H7 B6 B6 B20 C25 C25 C25 C25 C25 C25 E20 E20 E20 E20 D19 D19 D19 E2 E2
B6 B6 B6 B6 B6 H7 B6 B6 B20 B20 C25 C25 C25 C25 C25 C25 E20 E20 E20 E20 D19 D19 E2 E2
B6 B6 B6 B6 B6 H7 B6 B6 B20 B20 B20 C25 C25 C25 C25 C25 C25 E20 E20 E20 E20 D19 E8 E8
B6 B6 B6 B6 B6 H7 B6 B6 B20 B20 B20 B20 B20 C25 C25 C25 C25 C25 E20 E20 E20 E20 E8 E8
B6 B6 B6 B6 B6 H7 B6 B6 B20 B20 B20 B20 B20 B20 C25 C25 C25 C25 C25 D16 D16 D16 E17 E8
"""
    private static let alphaH1OnlyCodes = """
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
"""
    private static let gradientIterativeH1Codes = """
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1 H1
"""
    private static let rgbIterativeCodes = """
D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7
D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7
D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7
D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7
D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7
D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7
C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8
C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8
C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8
C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8
C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8
C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8
B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14
B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14
B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14
B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14
B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14
B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15 A14 A14 A14 A14 A14 A14
A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15
A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15
A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15
A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15
A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15
A14 A14 A14 A14 A14 A14 B8 B8 B8 B8 B8 B8 C7 C7 C7 C7 C7 C7 D15 D15 D15 D15 D15 D15
"""
    private static let gradientStandardCodes = """
H5 H5 H5 H5 H5 H5 H5 G8 G8 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G8 G8 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G17 G8 E22 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7 E7
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
H5 H5 H5 H5 H5 H5 H5 G17 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
H5 H5 H5 H5 H5 H5 H5 H4 G17 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3
B12 B12 H5 H5 H5 H5 H5 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 H5 H5 H5 H5 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 B12 H5 H5 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 B12 B12 H5 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 H5 H5 H5 H5 H5 H5 H5 H5 H5 H5 H5 H5 H5 G17 G17 G17 G17 G17 G17 E7 E7
B12 B12 B12 B12 B12 H5 H4 H4 H4 H4 H4 H4 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 B12 B12 B12 H4 H4 H4 H4 H4 H4 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E3 E3
B12 B12 B12 B12 B12 B12 H4 H4 H4 H4 H4 H4 H4 H4 H4 E22 E22 E22 E22 E22 E22 E22 E3 E3
B8 B12 B12 B12 B12 B12 C11 H4 H4 H4 H4 H4 H4 H4 H4 E20 D19 E22 E22 E22 E22 E22 E3 E3
B8 B8 B8 B12 B12 B12 C11 C11 C25 C25 H4 H4 H4 H4 H4 E20 E20 D19 D19 D19 E22 E22 E2 E3
B8 B8 B8 B6 B6 B12 B6 C11 C25 C25 C25 C25 H4 H4 H4 E20 E20 E20 D19 D19 D19 D19 E2 E2
B8 B8 B6 B6 B6 B12 B6 B6 B20 C25 C25 C25 C25 C25 C25 E20 E20 E20 E20 D19 D19 D19 E2 E2
B6 B6 B6 B6 B6 B12 B6 B6 B20 B20 C25 C25 C25 C25 C25 C25 E20 E20 E20 E20 D19 D19 E2 E2
B6 B6 B6 B6 B6 B12 B6 B6 B20 B20 B20 C25 C25 C25 C25 C25 C25 E20 E20 E20 E20 D19 E8 E8
B6 B6 B6 B6 B6 B12 B6 B6 B20 B20 B20 B20 B20 C25 C25 C25 C25 C25 E20 E20 E20 E20 E8 E8
B6 B6 B6 B6 B6 B12 B6 B6 B20 B20 B20 B20 B20 B20 C25 C25 C25 C25 C25 D16 D16 D16 E17 E8
"""
    private static let gradientSampledCodes = """
F11 F11 F11 F11 F11 F11 F11 F11 F11 F11 F11 F11 F11 E6 E6 E6 E6 E6 E6 E6 E6 E6 E6 E6
G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 E6 E6 E6 E6 E6 E6 E6 E6 E6 E6 E6
G17 G17 G17 G17 G17 F11 G17 G17 G17 G17 G17 G17 G17 E6 E6 E6 E6 E6 E6 E6 E6 E6 E6 E6
G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D6 E6 E6 E6 E6 E6 E6 E6 E6 E6 E6
G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D6 D6 D6 D6 D6 D6 D6 D6 D6 D6 D6
G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D6 D6 D6 D6 D6 D6 D6 D6 D6 D6 D6
G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D6 D6 D6 D6 D6 D6 D6 D6 D6 D6 E3
G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D6 D6 D6 D6 D6 D6 D6 D6 E3 E3 E3
G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D2 E3 E3 E3 E3 E3 E3 E3 E3 E3 E3
B8 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D2 E3 E3 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D2 E3 E3 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 D2 E3 E3 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17 G17
B8 B8 B8 B8 B8 G17 C10 C10 G17 G17 G17 G17 G17 G17 G17 G17 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 G17 C10 C10 C10 C10 G17 G17 G17 G17 G17 G17 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 G17 C10 C10 C10 C10 C10 C10 G17 G17 G17 G17 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 G17 C10 C10 C10 C10 C10 C10 C10 C10 G17 G17 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 B8 C10 C10 C10 C10 C10 C10 C10 C10 C10 C10 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 B8 C10 C10 C10 C10 C10 C10 C10 C10 C10 C10 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 B8 C10 C10 C10 C10 C10 C10 C10 C10 C10 C10 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 B8 C10 C10 C10 C10 C10 C10 C10 C10 C10 C10 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 B8 C10 C10 C10 C10 C10 C10 C10 C10 C10 C10 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 B8 C10 C10 C10 C10 C10 C10 C10 C10 C10 C10 E3 E3 E3 E3 E3 E3 E3 E3
B8 B8 B8 B8 B8 B8 C10 C10 C10 C10 C10 C10 C10 C10 C10 C10 E3 E3 E3 E3 E3 E3 E3 E3
"""
    private static let checkerCodes = """
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4
H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2 H4 H2
"""
    private static let alphaCodes = """
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
EMPTY EMPTY H7 H7 H7 H7 H7 H7 H7 H1 EMPTY EMPTY
EMPTY EMPTY H7 H7 H7 H7 H7 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H7 H7 H7 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H7 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY H1 H1 H1 H1 H1 H1 H1 H1 EMPTY EMPTY
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY EMPTY
"""
}
