import Foundation

public struct LabColor: Equatable, Sendable {
    public let l: Double
    public let a: Double
    public let b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public init(red: Double, green: Double, blue: Double) {
        func linearize(_ channel: Double) -> Double {
            channel > 0.04045 ? pow((channel + 0.055) / 1.055, 2.4) : channel / 12.92
        }
        let r = linearize(red), g = linearize(green), b = linearize(blue)

        let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
        let y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.00000
        let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t) + (16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)

        self.l = (116.0 * fy) - 16.0
        self.a = 500.0 * (fx - fy)
        self.b = 200.0 * (fy - fz)
    }

    public func distance(to other: LabColor) -> Double {
        let dl = l - other.l
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// Inverse of `init(red:green:blue:)` — needed because pixel data flows through this app as
    /// Lab (see `PixelImage`), but hue/saturation classification for rule-based color matching
    /// needs RGB/HSL. Clamped to [0, 1] since out-of-gamut Lab values can otherwise overshoot.
    public var rgb: (red: Double, green: Double, blue: Double) {
        let fy = (l + 16.0) / 116.0
        let fx = fy + a / 500.0
        let fz = fy - b / 200.0

        func finv(_ t: Double) -> Double {
            let cube = t * t * t
            return cube > 0.008856 ? cube : (t - 16.0 / 116.0) / 7.787
        }
        let x = finv(fx) * 0.95047
        let y = finv(fy) * 1.00000
        let z = finv(fz) * 1.08883

        let rLinear = x * 3.2406 + y * -1.5372 + z * -0.4986
        let gLinear = x * -0.9689 + y * 1.8758 + z * 0.0415
        let bLinear = x * 0.0557 + y * -0.2040 + z * 1.0570

        func gammaCorrect(_ c: Double) -> Double {
            let clamped = max(0.0, c)
            let companded = clamped > 0.0031308 ? 1.055 * pow(clamped, 1.0 / 2.4) - 0.055 : 12.92 * clamped
            return min(1.0, max(0.0, companded))
        }
        return (gammaCorrect(rLinear), gammaCorrect(gLinear), gammaCorrect(bLinear))
    }
}

extension MardColor {
    public var lab: LabColor {
        LabColor(red: red, green: green, blue: blue)
    }
}

extension HSLColor {
    public init(lab: LabColor) {
        let rgb = lab.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

public enum ColorMatcher {
    /// Rule-constrained nearest-color match: filters the palette down through lightness class,
    /// saturation class, and hue proximity (excluding near-complementary hues) before picking the
    /// closest remaining candidate by Lab distance. Each filter stage falls back to the previous
    /// stage's candidate set if it would otherwise eliminate every option, so there's always a
    /// result. `forcedLightness` overrides the target's own lightness class — used by contour
    /// pixels, which must quantize to a dark bead regardless of the source pixel's exact tone.
    ///
    /// This is the hot path (called per-cell, per-iteration by `PaletteOptimizer`), so it does a
    /// single linear-scan minimum rather than routing through `rankedCandidates`' sort — sorting
    /// recomputes Lab distance O(n log n) times per call instead of O(n), which was measured to
    /// blow the pattern generator's 10s budget on a 100x100 grid.
    public static func nearest(
        to color: LabColor,
        in palette: [MardColor],
        forcedLightness: LightnessClass? = nil
    ) -> MardColor {
        let candidates = filteredCandidates(for: color, in: palette, forcedLightness: forcedLightness)
        var best = candidates[0]
        var bestDistance = color.distance(to: best.lab)
        for candidate in candidates.dropFirst() {
            let distance = color.distance(to: candidate.lab)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    /// Same rule-constrained filtering as `nearest`, but returns every surviving candidate sorted
    /// by ascending Lab distance (nearest first). Used by gradient-order enforcement, which needs
    /// to step to the *next*-best rule-compliant color rather than only the single best one; that
    /// call site is far less frequent than `nearest`'s per-pixel hot path, so the sort cost is fine.
    public static func rankedCandidates(
        for color: LabColor,
        in palette: [MardColor],
        forcedLightness: LightnessClass? = nil
    ) -> [MardColor] {
        filteredCandidates(for: color, in: palette, forcedLightness: forcedLightness)
            .enumerated()
            .sorted { a, b in
                let da = color.distance(to: a.element.lab)
                let db = color.distance(to: b.element.lab)
                // Stable tie-break: preserve original palette order when distances are equal.
                return da != db ? da < db : a.offset < b.offset
            }
            .map(\.element)
    }

    private static func filteredCandidates(
        for color: LabColor,
        in palette: [MardColor],
        forcedLightness: LightnessClass?
    ) -> [MardColor] {
        precondition(!palette.isEmpty, "palette must not be empty")

        let targetHSL = HSLColor(lab: color)
        let targetLightness = forcedLightness ?? targetHSL.lightnessClass

        let lightnessFiltered = palette.filter { $0.hsl.lightnessClass == targetLightness }
        let afterLightness = lightnessFiltered.isEmpty ? palette : lightnessFiltered

        let targetSaturation = targetHSL.saturationClass
        let saturationFiltered = afterLightness.filter { $0.hsl.saturationClass == targetSaturation }
        let afterSaturation = saturationFiltered.isEmpty ? afterLightness : saturationFiltered

        if targetSaturation == .neutral {
            // Hue is meaningless for near-gray colors, so skip the complementary-hue filter.
            return afterSaturation
        }
        let hueFiltered = afterSaturation.filter {
            targetHSL.hueDistance(to: $0.hsl) <= HSLColor.complementaryHueThreshold
        }
        return hueFiltered.isEmpty ? afterSaturation : hueFiltered
    }
}
