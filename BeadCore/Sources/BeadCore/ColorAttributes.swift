import Foundation

public enum LightnessClass: Equatable, Sendable {
    case light
    case dark
}

public enum SaturationClass: Equatable, Sendable {
    case neutral
    case low
    case high
}

/// HSL representation used to classify colors for rule-based matching (lightness/saturation
/// bucket + hue distance), separate from `LabColor` which is used for perceptual distance.
public struct HSLColor: Equatable, Sendable {
    public static let lightnessThreshold = 0.5
    public static let neutralSaturationThreshold = 0.12
    public static let highSaturationThreshold = 0.35
    public static let complementaryHueThreshold = 150.0

    public let hue: Double
    public let saturation: Double
    public let lightness: Double

    public init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    public init(red: Double, green: Double, blue: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        let l = (maxC + minC) / 2

        let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))

        var h: Double
        if delta == 0 {
            h = 0
        } else if maxC == red {
            h = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxC == green {
            h = 60 * (((blue - red) / delta) + 2)
        } else {
            h = 60 * (((red - green) / delta) + 4)
        }
        if h < 0 { h += 360 }

        self.hue = h
        self.saturation = s
        self.lightness = l
    }

    public var lightnessClass: LightnessClass {
        lightness >= HSLColor.lightnessThreshold ? .light : .dark
    }

    /// The HSL `saturation` formula divides by `1 - |2L - 1|`, which approaches zero (and makes
    /// `saturation` spike toward 1) for any near-white or near-black color, even ones with almost
    /// no actual color cast — e.g. "FDFBFF" computes saturation ~1.0 despite being visually gray.
    /// `chroma` recovers the original max-min channel spread (the inverse of that formula), which
    /// stays well-behaved at the lightness extremes and is what saturation classification should
    /// actually be based on.
    public var chroma: Double {
        saturation * (1 - abs(2 * lightness - 1))
    }

    public var saturationClass: SaturationClass {
        if chroma < HSLColor.neutralSaturationThreshold { return .neutral }
        return chroma >= HSLColor.highSaturationThreshold ? .high : .low
    }

    /// Shortest distance between two hues on the color circle, in degrees [0, 180].
    public func hueDistance(to other: HSLColor) -> Double {
        let diff = abs(hue - other.hue).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }
}

extension MardColor {
    public var hsl: HSLColor {
        HSLColor(red: red, green: green, blue: blue)
    }
}
