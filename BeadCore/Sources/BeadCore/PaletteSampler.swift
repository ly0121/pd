import Foundation

/// Deterministically picks a subset of colors evenly spread across the hue wheel — used as a
/// stand-in for the official MARD "12色/24色/48色/..." preset kits, whose exact color-number
/// lists this app doesn't have yet. Sorting by hue first (rather than sampling in palette
/// declaration order) means the sampled set actually covers the color wheel instead of being
/// biased toward whichever series happens to come first alphabetically.
public enum PaletteSampler {
    public static func sample(count: Int, from palette: [MardColor]) -> [MardColor] {
        guard count < palette.count else { return palette }
        guard count > 0 else { return [] }

        let sorted = palette.sorted { $0.hsl.hue < $1.hsl.hue }
        var result = [MardColor]()
        result.reserveCapacity(count)
        for i in 0..<count {
            let index = (i * sorted.count) / count
            result.append(sorted[index])
        }
        return result
    }
}
