import BeadCore
import Foundation

struct ColorUsage: Identifiable {
    let color: MardColor
    let count: Int
    var id: String { color.code }
}

enum ColorUsageCalculator {
    static func usages(for grid: BeadGrid) -> [ColorUsage] {
        var counts: [String: Int] = [:]
        var colorByCode: [String: MardColor] = [:]
        for color in grid.colors {
            guard color != .empty else { continue } // background isn't a bead color to buy/count
            counts[color.code, default: 0] += 1
            colorByCode[color.code] = color
        }
        return counts
            .compactMap { code, count in colorByCode[code].map { ColorUsage(color: $0, count: count) } }
            .sorted { $0.count > $1.count }
    }
}
