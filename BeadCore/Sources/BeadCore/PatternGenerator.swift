import CoreGraphics
import Foundation

public struct PatternGenerationOptions: Sendable {
    public let columns: Int
    public let rows: Int
    public let palette: [MardColor]
    public let iterations: Int
    public let compactness: Double
    public let maxIsolatedCount: Int

    public init(
        columns: Int, rows: Int, palette: [MardColor] = MardPalette.standard221,
        iterations: Int = 10, compactness: Double = 10.0, maxIsolatedCount: Int = 2
    ) {
        self.columns = columns
        self.rows = rows
        self.palette = palette
        self.iterations = iterations
        self.compactness = compactness
        self.maxIsolatedCount = maxIsolatedCount
    }
}

public enum PatternGenerator {
    /// Runs the full image -> bead grid pipeline: importance map, contour detection, SLIC +
    /// palette joint optimization (forcing dark outlines per contour weight, and assigning
    /// `MardColor.empty` for background per `foregroundWeights`), isolated-noise cleanup, then
    /// gradient-order repair.
    public static func generate(
        image: PixelImage,
        importance: ImportanceMap,
        options: PatternGenerationOptions,
        foregroundWeights: [Double]? = nil
    ) -> BeadGrid {
        let contourWeights = ContourDetector.detect(image)
        let optimized = PaletteOptimizer.optimize(
            image: image, columns: options.columns, rows: options.rows,
            importance: importance, palette: options.palette,
            iterations: options.iterations, compactness: options.compactness,
            contourWeights: contourWeights, foregroundWeights: foregroundWeights
        )
        let grid = PaletteOptimizer.makeGrid(from: optimized)
        let cleaned = NoiseCleaner.clean(grid, maxIsolatedCount: options.maxIsolatedCount)
        return GradientOrderEnforcer.enforce(cleaned, sourceStats: optimized.cellStats, palette: options.palette)
    }

    /// Convenience overload that reads pixels directly from a CGImage and generates the
    /// importance map via the given provider. `foregroundMaskProvider` defaults to
    /// `UniformForegroundMaskProvider` (always nil, i.e. no background removal) so existing
    /// call sites that don't care about background removal are unaffected.
    public static func generate(
        cgImage: CGImage,
        importanceProvider: ImportanceMapProvider,
        options: PatternGenerationOptions,
        foregroundMaskProvider: ForegroundMaskProvider = UniformForegroundMaskProvider()
    ) -> BeadGrid {
        let image = PixelImage(cgImage: cgImage)
        let importance = importanceProvider.importanceMap(for: cgImage)
        let foregroundWeights = foregroundMaskProvider.foregroundMask(for: cgImage)
        return generate(image: image, importance: importance, options: options, foregroundWeights: foregroundWeights)
    }
}

extension PixelImage {
    public init(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &rawData, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [LabColor]()
        pixels.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let r = Double(rawData[i * 4 + 0]) / 255.0
            let g = Double(rawData[i * 4 + 1]) / 255.0
            let b = Double(rawData[i * 4 + 2]) / 255.0
            pixels.append(LabColor(red: r, green: g, blue: b))
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
