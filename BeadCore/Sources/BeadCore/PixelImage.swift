import Foundation

public struct PixelImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [LabColor]

    public init(width: Int, height: Int, pixels: [LabColor]) {
        precondition(pixels.count == width * height, "pixel count must equal width * height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, rgb: [(red: Double, green: Double, blue: Double)]) {
        self.init(width: width, height: height, pixels: rgb.map { LabColor(red: $0.red, green: $0.green, blue: $0.blue) })
    }

    public func pixel(x: Int, y: Int) -> LabColor {
        pixels[y * width + x]
    }
}

public struct ImportanceMap: Sendable {
    public let width: Int
    public let height: Int
    public let weights: [Double]

    public init(width: Int, height: Int, weights: [Double]) {
        precondition(weights.count == width * height, "weight count must equal width * height")
        self.width = width
        self.height = height
        self.weights = weights
    }

    public static func uniform(width: Int, height: Int) -> ImportanceMap {
        ImportanceMap(width: width, height: height, weights: [Double](repeating: 1.0, count: width * height))
    }

    public func weight(x: Int, y: Int) -> Double {
        weights[y * width + x]
    }
}

public struct BeadGrid: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public var colors: [MardColor]

    public init(columns: Int, rows: Int, colors: [MardColor]) {
        precondition(colors.count == columns * rows, "color count must equal columns * rows")
        self.columns = columns
        self.rows = rows
        self.colors = colors
    }

    public func color(col: Int, row: Int) -> MardColor {
        colors[row * columns + col]
    }

    public mutating func setColor(_ color: MardColor, col: Int, row: Int) {
        colors[row * columns + col] = color
    }
}
