import CoreGraphics
import Foundation

public enum FixedCell: Equatable, Sendable {
    case outside
    case hole
}

public enum SourceAlphaCells {
    /// Classifies transparent source pixels before reducing them to bead cells. Image rows are
    /// top-to-bottom, matching BeadGrid's row-major storage.
    public static func classify(alpha: [UInt8], width: Int, height: Int, columns: Int, rows: Int) -> [FixedCell?] {
        precondition(width > 0 && height > 0 && columns > 0 && rows > 0 && alpha.count == width * height)
        let count = width * height
        var connected = [Bool](repeating: false, count: count)
        var queue = [Int]()
        queue.reserveCapacity(count)

        func add(_ index: Int) {
            guard alpha[index] <= 127, !connected[index] else { return }
            connected[index] = true
            queue.append(index)
        }
        for x in 0..<width {
            add(x)
            add((height - 1) * width + x)
        }
        for y in 0..<height {
            add(y * width)
            add(y * width + width - 1)
        }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            if x > 0 { add(index - 1) }
            if x + 1 < width { add(index + 1) }
            if y > 0 { add(index - width) }
            if y + 1 < height { add(index + width) }
        }

        var outsideCount = [Int](repeating: 0, count: columns * rows)
        var holeCount = [Int](repeating: 0, count: columns * rows)
        var total = [Int](repeating: 0, count: columns * rows)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let cell = min(rows - 1, y * rows / height) * columns + min(columns - 1, x * columns / width)
                total[cell] += 1
                if alpha[index] <= 127 {
                    if connected[index] { outsideCount[cell] += 1 }
                    else { holeCount[cell] += 1 }
                }
            }
        }
        return (0..<(columns * rows)).map { cell in
            if total[cell] == 0 {
                let x = min(width - 1, ((cell % columns) * 2 + 1) * width / (2 * columns))
                let y = min(height - 1, ((cell / columns) * 2 + 1) * height / (2 * rows))
                let index = y * width + x
                guard alpha[index] <= 127 else { return nil }
                return connected[index] ? .outside : .hole
            }
            if outsideCount[cell] * 2 >= total[cell] { return .outside }
            if holeCount[cell] * 2 >= total[cell] { return .hole }
            return nil
        }
    }

    public static func classify(source: CGImage, columns: Int, rows: Int) -> [FixedCell?] {
        let width = source.width
        let height = source.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: &rgba, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else {
            return [FixedCell?](repeating: nil, count: columns * rows)
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        if stride(from: 3, to: rgba.count, by: 4).allSatisfy({ rgba[$0] == 255 }) {
            return [FixedCell?](repeating: nil, count: columns * rows)
        }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        return classify(alpha: alpha, width: width, height: height, columns: columns, rows: rows)
    }
}
