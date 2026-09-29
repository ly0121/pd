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
    /// Matches by continuous Lab distance within the caller's palette. Hard lightness/chroma
    /// classes would discard closer colors at arbitrary thresholds, flattening tonal detail.
    /// Only an explicit `forcedLightness` restricts candidates, to protect detected dark outlines.
    /// If that class is absent, fall back to the supplied palette — never add unowned colors.
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
        let candidates = filteredCandidates(in: palette, forcedLightness: forcedLightness)
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

    /// Uses the same candidates as `nearest`, sorted by ascending Lab distance. Gradient-order
    /// enforcement can then choose the closest alternative that preserves the source's tone order.
    public static func rankedCandidates(
        for color: LabColor,
        in palette: [MardColor],
        forcedLightness: LightnessClass? = nil
    ) -> [MardColor] {
        filteredCandidates(in: palette, forcedLightness: forcedLightness)
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
        in palette: [MardColor],
        forcedLightness: LightnessClass?
    ) -> [MardColor] {
        precondition(!palette.isEmpty, "palette must not be empty")
        guard let forcedLightness else { return palette }
        let filtered = palette.filter { $0.hsl.lightnessClass == forcedLightness }
        return filtered.isEmpty ? palette : filtered
    }
}
