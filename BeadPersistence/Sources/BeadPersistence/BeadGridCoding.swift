import BeadCore
import Foundation

public enum BeadGridCodingError: Error, Equatable {
    case codeCountMismatch(expected: Int, actual: Int)
    case unknownColorCode(String)
}

public enum BeadGridCoding {
    private static let separator = ","

    public static func encode(_ grid: BeadGrid) -> String {
        grid.colors.map(\.code).joined(separator: separator)
    }

    /// Decodes a comma-separated code string back into a BeadGrid, resolving each code against
    /// `palette`. Throws rather than silently substituting a fallback color, since a decode
    /// failure means the persisted data and the app's palette have diverged — silently
    /// substituting would corrupt the pattern without any signal to the caller.
    public static func decode(_ codes: String, columns: Int, rows: Int, palette: [MardColor]) throws -> BeadGrid {
        let codeList = codes.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        let expectedCount = columns * rows
        guard codeList.count == expectedCount else {
            throw BeadGridCodingError.codeCountMismatch(expected: expectedCount, actual: codeList.count)
        }

        var paletteByCode: [String: MardColor] = [:]
        for color in palette {
            paletteByCode[color.code] = color
        }

        var colors = [MardColor]()
        colors.reserveCapacity(expectedCount)
        for code in codeList {
            guard let color = paletteByCode[code] else {
                throw BeadGridCodingError.unknownColorCode(code)
            }
            colors.append(color)
        }

        return BeadGrid(columns: columns, rows: rows, colors: colors)
    }
}
