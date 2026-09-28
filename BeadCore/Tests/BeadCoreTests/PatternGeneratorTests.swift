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
}
