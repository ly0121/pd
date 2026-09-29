import Foundation

/// Detects dark outlines from local darkness, not general edge magnitude. A smooth gradient
/// or the light side of an edge must not force a cell into a darker palette class. Absolute
/// lightness also limits the signal so midgray detail on white stays midgray, not a dark outline.
public enum ContourDetector {
    /// Minimum Lab L difference below the surrounding 3x3 mean for outline evidence.
    static let darknessGateThreshold = 2.0
    /// Local darkness difference that saturates the outline weight to 1.
    static let contrastNormalizationScale = 20.0
    /// Fade protection from full strength at L=30 to zero at L=50.
    static let darkLightnessLimit = 50.0
    static let darkLightnessFade = 20.0

    /// Returns one dark-outline weight in [0, 1] per source pixel, in row-major order.
    public static func detect(_ image: PixelImage) -> [Double] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        func lightness(_ x: Int, _ y: Int) -> Double {
            let col = min(max(x, 0), width - 1)
            let row = min(max(y, 0), height - 1)
            return image.pixels[row * width + col].l
        }

        var weights = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = image.pixels[index].l
                let neighborMean = (
                    lightness(x - 1, y - 1) + lightness(x, y - 1) + lightness(x + 1, y - 1)
                    + lightness(x - 1, y) + lightness(x + 1, y)
                    + lightness(x - 1, y + 1) + lightness(x, y + 1) + lightness(x + 1, y + 1)
                ) / 8.0
                let darkerAmount = neighborMean - value
                guard darkerAmount > darknessGateThreshold else { continue }
                let darkness = min(1.0, max(0.0, (darkLightnessLimit - value) / darkLightnessFade))
                weights[index] = min(1.0, darkerAmount / contrastNormalizationScale) * darkness
            }
        }
        return weights
    }
}
