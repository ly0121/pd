import Foundation

/// Detects contour/outline pixels — where beading needs to keep a firm dark line rather than
/// let a pixel wash out into a neighboring lighter color. The primary signal is local contrast
/// (how much darker a pixel is than its surrounding 3x3 mean), not Sobel edge magnitude: Sobel is
/// the *derivative* of intensity, and for a thin symmetric line the derivative is ~0 exactly at
/// the line's center (same reason a derivative vanishes at a peak) even though that's precisely
/// the pixel the user's rule ("轮廓勾边保持深色" — keep dark outlines dark) cares about. Sobel
/// magnitude is kept only as a secondary, damped signal for edge pixels that aren't themselves
/// darker than their neighborhood (e.g. the light side of an edge).
public enum ContourDetector {
    /// How much darker (in Lab L units, roughly 0-100) a pixel must be than its local 3x3 mean
    /// before it's treated as a genuine dark-outline pixel rather than incidental noise.
    static let darknessGateThreshold = 2.0

    /// Lab L units of "darker than local mean" that saturates the contour weight to 1.0.
    static let contrastNormalizationScale = 20.0

    /// Weight multiplier applied to normalized Sobel edge magnitude for pixels that are on an
    /// edge but not darker than their neighborhood — keeps the weight map continuous without
    /// treating non-dark edges as full-strength outlines.
    static let nonDarkEdgeDamping = 0.3

    /// Returns one weight in [0, 1] per pixel (row-major, matching `PixelImage.pixels`), where
    /// higher values indicate a stronger dark contour/outline at that pixel.
    public static func detect(_ image: PixelImage) -> [Double] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
        func lightness(_ x: Int, _ y: Int) -> Double {
            image.pixels[clamp(y, 0, height - 1) * width + clamp(x, 0, width - 1)].l
        }

        var magnitudes = [Double](repeating: 0, count: width * height)
        var localMeans = [Double](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let tl = lightness(x - 1, y - 1), t = lightness(x, y - 1), tr = lightness(x + 1, y - 1)
                let l = lightness(x - 1, y), r = lightness(x + 1, y)
                let bl = lightness(x - 1, y + 1), b = lightness(x, y + 1), br = lightness(x + 1, y + 1)

                let gx = (tr + 2 * r + br) - (tl + 2 * l + bl)
                let gy = (bl + 2 * b + br) - (tl + 2 * t + tr)
                let magnitude = (gx * gx + gy * gy).squareRoot()

                let idx = y * width + x
                magnitudes[idx] = magnitude
                localMeans[idx] = (tl + t + tr + l + r + bl + b + br) / 8.0
            }
        }

        let maxMagnitude = max(magnitudes.max() ?? 0, 0.0001)

        var weights = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let darkerAmount = localMeans[idx] - image.pixels[idx].l
                if darkerAmount > darknessGateThreshold {
                    weights[idx] = min(1.0, darkerAmount / contrastNormalizationScale)
                } else {
                    weights[idx] = (magnitudes[idx] / maxMagnitude) * nonDarkEdgeDamping
                }
            }
        }
        return weights
    }
}
