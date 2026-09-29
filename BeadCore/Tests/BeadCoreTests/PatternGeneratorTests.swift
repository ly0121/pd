import CoreGraphics
import Dispatch
import Testing
@testable import BeadCore

@Suite("PatternGenerator")
struct PatternGeneratorTests {
    @Test("generate produces a grid with the requested dimensions from a flat image")
    func generateProducesRequestedDimensions() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 16, height: 16, pixels: [LabColor](repeating: gray, count: 256))
        let importance = ImportanceMap.uniform(width: 16, height: 16)
        let options = PatternGenerationOptions(columns: 8, rows: 8)

        let grid = PatternGenerator.generate(image: image, importance: importance, options: options)

        #expect(grid.columns == 8)
        #expect(grid.rows == 8)
        #expect(grid.colors.count == 64)
    }

    @Test("PixelImage(cgImage:) extracts pixels matching the image's drawn colors")
    func pixelImageFromCGImageExtractsColors() {
        let width = 4, height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let image = PixelImage(cgImage: cgImage)

        #expect(image.width == 4)
        #expect(image.height == 4)
        let expectedRed = LabColor(red: 1, green: 0, blue: 0)
        for pixel in image.pixels {
            #expect(abs(pixel.l - expectedRed.l) < 1.0)
            #expect(abs(pixel.a - expectedRed.a) < 1.0)
            #expect(abs(pixel.b - expectedRed.b) < 1.0)
        }
    }

    @Test("end-to-end generation from a synthetic CGImage completes and covers the full palette-agnostic pipeline")
    func endToEndGenerationFromCGImage() {
        let width = 64, height = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        context.fillEllipse(in: CGRect(x: 16, y: 16, width: 32, height: 32))
        let cgImage = context.makeImage()!

        let options = PatternGenerationOptions(columns: 20, rows: 20)
        let grid = PatternGenerator.generate(
            cgImage: cgImage,
            importanceProvider: VisionSaliencyImportanceMapProvider(),
            options: options
        )

        #expect(grid.columns == 20)
        #expect(grid.rows == 20)
        #expect(grid.colors.count == 400)
        // Every assigned color must genuinely be a member of the requested palette.
        let paletteCodes = Set(MardPalette.standard221.map(\.code))
        #expect(grid.colors.allSatisfy { paletteCodes.contains($0.code) })
    }

    @Test("realistic 100x100 grid with the full 221-color palette completes in reasonable time")
    func realisticSizeCompletesInReasonableTime() {
        let width = 400, height = 400
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.85, green: 0.75, blue: 0.2, alpha: 1)
        context.fillEllipse(in: CGRect(x: 100, y: 100, width: 200, height: 200))
        let cgImage = context.makeImage()!

        let options = PatternGenerationOptions(columns: 100, rows: 100)

        let start = DispatchTime.now()
        let grid = PatternGenerator.generate(
            cgImage: cgImage,
            importanceProvider: VisionSaliencyImportanceMapProvider(),
            options: options
        )
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        #expect(grid.columns == 100)
        #expect(grid.rows == 100)
        #expect(elapsedSeconds < 10.0)
    }

    @Test("exact H2 and H4 checkerboards remain representable in either palette")
    func exactCheckerboardPreservesColors() {
        let white = MardPalette.standard221.first { $0.code == "H2" }!
        let gray = MardPalette.standard221.first { $0.code == "H4" }!
        let columns = 32, cellPixels = 6, width = 192
        let pixels = (0..<width * width).map { index in
            ((index % width / cellPixels + index / width / cellPixels) % 2 == 0 ? white : gray).lab
        }
        let image = PixelImage(width: width, height: width, pixels: pixels)
        for palette in [MardPalette.standard221, MardPalette.allColors] {
            let grid = PatternGenerator.generate(
                image: image, importance: .uniform(width: width, height: width),
                options: PatternGenerationOptions(columns: columns, rows: columns, palette: palette)
            )
            let expected = (0..<columns * columns).map { index in
                (index % columns + index / columns) % 2 == 0 ? white : gray
            }
            #expect(grid.colors == expected)
        }
    }

    @Test("smooth neutral ramps preserve light tones and order within the selected palette")
    func smoothRampPreservesTonalRange() {
        let columns = 32, cellPixels = 6, width = 192
        let pixels = (0..<width * cellPixels).map { index in
            let channel = 0.3 + 0.5 * Double(index % width) / Double(width - 1)
            return LabColor(red: channel, green: channel, blue: channel)
        }
        let image = PixelImage(width: width, height: cellPixels, pixels: pixels)
        let importance = ImportanceMap.uniform(width: width, height: cellPixels)
        let labels = SuperpixelSegmenter.initialLabels(width: width, height: cellPixels, columns: columns, rows: 1)
        let stats = SuperpixelSegmenter.cellStats(
            image: image, columns: columns, rows: 1, importance: importance, labels: labels
        )
        for palette in [MardPalette.standard221, MardPalette.allColors] {
            let grid = PatternGenerator.generate(
                image: image, importance: importance,
                options: PatternGenerationOptions(columns: columns, rows: 1, palette: palette)
            )
            #expect(grid.colors.allSatisfy { palette.contains($0) })
            #expect(grid.colors.last!.lab.l > 65)
            #expect(zip(grid.colors, grid.colors.dropFirst()).allSatisfy { $0.lab.l <= $1.lab.l })
            let meanSquaredError = zip(stats, grid.colors).reduce(0.0) { sum, pair in
                let distance = pair.0.color.distance(to: pair.1.lab)
                return sum + distance * distance
            } / Double(columns)
            #expect(meanSquaredError.squareRoot() < 12)
        }
    }

    /// Fake provider standing in for a real Vision detection: marks the left half of the image
    /// as background (weight 0) and the right half as foreground (weight 1), so the test can
    /// assert on a known, deterministic split rather than depending on Vision's actual subject
    /// detection succeeding on a synthetic image.
    private struct HalfSplitForegroundMaskProvider: ForegroundMaskProvider {
        func foregroundMask(for image: CGImage) -> [Double]? {
            var weights = [Double](repeating: 0, count: image.width * image.height)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    weights[y * image.width + x] = x < image.width / 2 ? 0.0 : 1.0
                }
            }
            return weights
        }
    }

    @Test("generate assigns MardColor.empty to cells in the background half when given a foreground mask provider")
    func generateAppliesBackgroundRemoval() {
        let width = 40, height = 40
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let options = PatternGenerationOptions(columns: 16, rows: 8)
        let grid = PatternGenerator.generate(
            cgImage: cgImage,
            importanceProvider: UniformImportanceMapProvider(),
            options: options,
            foregroundMaskProvider: HalfSplitForegroundMaskProvider()
        )

        // Only check the outer quarter of columns on each side, well clear of the seam at the
        // midpoint — SLIC's spatial boundary refinement can drift a few cells across the mask's
        // exact pixel split on a flat-color image with no color signal to anchor it, which is
        // expected and not what this test is checking.
        let quarter = grid.columns / 4
        for row in 0..<grid.rows {
            for col in 0..<quarter {
                #expect(grid.color(col: col, row: row) == .empty)
            }
            for col in (grid.columns - quarter)..<grid.columns {
                #expect(grid.color(col: col, row: row) != .empty)
            }
        }
    }

    @Test("generate leaves every cell as a real palette color when the default UniformForegroundMaskProvider is used")
    func generateWithoutBackgroundRemovalNeverProducesEmpty() {
        let width = 40, height = 40
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let options = PatternGenerationOptions(columns: 8, rows: 8)
        let grid = PatternGenerator.generate(
            cgImage: cgImage,
            importanceProvider: UniformImportanceMapProvider(),
            options: options
        )

        #expect(grid.colors.allSatisfy { $0 != .empty })
    }
}
