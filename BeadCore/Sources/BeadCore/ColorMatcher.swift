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
}

extension MardColor {
    public var lab: LabColor {
        LabColor(red: red, green: green, blue: blue)
    }
}

public enum ColorMatcher {
    public static func nearest(to color: LabColor, in palette: [MardColor]) -> MardColor {
        precondition(!palette.isEmpty, "palette must not be empty")
        var best = palette[0]
        var bestDistance = color.distance(to: best.lab)
        for candidate in palette.dropFirst() {
            let distance = color.distance(to: candidate.lab)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }
}
