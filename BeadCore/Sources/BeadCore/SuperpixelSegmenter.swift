import Foundation

public struct CellStats: Sendable, Equatable {
    public var color: LabColor
    public var centerX: Double
    public var centerY: Double
    public var pixelCount: Int
    /// Mean contour weight (see `ContourDetector`) across this cell's assigned pixels, in [0, 1].
    /// Zero when no `contourWeights` were supplied to `cellStats(...)`.
    public var contourFraction: Double = 0
    /// Mean foreground-probability weight (see `ForegroundMaskProvider`) across this cell's
    /// assigned pixels, in [0, 1]. Zero when no `foregroundWeights` were supplied to
    /// `cellStats(...)` — which also means "not applicable," not "definitely background," so
    /// callers must gate on whether background removal was requested at all before acting on it.
    public var foregroundFraction: Double = 0
}

public struct SegmentationResult: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public let labels: [Int]

    public init(columns: Int, rows: Int, labels: [Int]) {
        precondition(labels.count > 0, "labels must not be empty")
        self.columns = columns
        self.rows = rows
        self.labels = labels
    }
}

public enum SuperpixelSegmenter {
    /// Maps a pixel coordinate to its initial rectangular grid cell index (row-major).
    public static func initialCellIndex(x: Int, y: Int, width: Int, height: Int, columns: Int, rows: Int) -> Int {
        let col = min(columns - 1, (x * columns) / width)
        let row = min(rows - 1, (y * rows) / height)
        return row * columns + col
    }

    public static func initialLabels(width: Int, height: Int, columns: Int, rows: Int) -> [Int] {
        var labels = [Int](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                labels[y * width + x] = initialCellIndex(x: x, y: y, width: width, height: height, columns: columns, rows: rows)
            }
        }
        return labels
    }

    /// Computes importance-weighted mean color and centroid position per cell.
    /// Cells with zero assigned pixels keep `fallback` (or a zero-filled stat if no fallback given).
    /// `contourWeights`/`foregroundWeights`, if supplied (one entry per pixel, matching
    /// `image.pixels`' layout), also produce each cell's mean `contourFraction`/`foregroundFraction`
    /// — omit either to leave that fraction at 0 and preserve prior behavior for callers that
    /// don't care about it.
    public static func cellStats(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        labels: [Int],
        fallback: [CellStats]? = nil,
        contourWeights: [Double]? = nil,
        foregroundWeights: [Double]? = nil
    ) -> [CellStats] {
        let cellCount = columns * rows
        var sumL = [Double](repeating: 0, count: cellCount)
        var sumA = [Double](repeating: 0, count: cellCount)
        var sumB = [Double](repeating: 0, count: cellCount)
        var sumX = [Double](repeating: 0, count: cellCount)
        var sumY = [Double](repeating: 0, count: cellCount)
        var sumWeight = [Double](repeating: 0, count: cellCount)
        var pixelCount = [Int](repeating: 0, count: cellCount)
        var sumContour = [Double](repeating: 0, count: cellCount)
        var sumForeground = [Double](repeating: 0, count: cellCount)

        for y in 0..<image.height {
            for x in 0..<image.width {
                let idx = y * image.width + x
                let cell = labels[idx]
                let weight = max(importance.weight(x: x, y: y), 0.0001)
                let color = image.pixels[idx]
                sumL[cell] += weight * color.l
                sumA[cell] += weight * color.a
                sumB[cell] += weight * color.b
                sumX[cell] += weight * Double(x)
                sumY[cell] += weight * Double(y)
                sumWeight[cell] += weight
                pixelCount[cell] += 1
                if let contourWeights {
                    sumContour[cell] += contourWeights[idx]
                }
                if let foregroundWeights {
                    sumForeground[cell] += foregroundWeights[idx]
                }
            }
        }

        var results = [CellStats]()
        results.reserveCapacity(cellCount)
        for cell in 0..<cellCount {
            if sumWeight[cell] > 0 {
                let contourFraction = pixelCount[cell] > 0 ? sumContour[cell] / Double(pixelCount[cell]) : 0
                let foregroundFraction = pixelCount[cell] > 0 ? sumForeground[cell] / Double(pixelCount[cell]) : 0
                results.append(CellStats(
                    color: LabColor(l: sumL[cell] / sumWeight[cell], a: sumA[cell] / sumWeight[cell], b: sumB[cell] / sumWeight[cell]),
                    centerX: sumX[cell] / sumWeight[cell],
                    centerY: sumY[cell] / sumWeight[cell],
                    pixelCount: pixelCount[cell],
                    contourFraction: contourFraction,
                    foregroundFraction: foregroundFraction
                ))
            } else if let fallback, cell < fallback.count {
                results.append(fallback[cell])
            } else {
                results.append(CellStats(color: LabColor(l: 0, a: 0, b: 0), centerX: 0, centerY: 0, pixelCount: 0))
            }
        }
        return results
    }

    /// Reassigns each pixel to the cell (its own, or a 4-connected neighbor) with the lowest
    /// combined color + spatial distance. `cellColors` lets callers override the color term
    /// (e.g. to use palette-projected colors instead of raw means) without affecting `centers`.
    public static func refine(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        labels: [Int],
        cellColors: [LabColor],
        centers: [CellStats],
        compactness: Double = 10.0
    ) -> [Int] {
        let cellCount = columns * rows
        precondition(cellColors.count == cellCount && centers.count == cellCount)

        let spatialScale = (Double(image.width * image.height) / Double(cellCount)).squareRoot()
        let maxImportance = max(importance.weights.max() ?? 1.0, 0.0001)

        var newLabels = labels
        for y in 0..<image.height {
            for x in 0..<image.width {
                let idx = y * image.width + x
                let ownCell = labels[idx]
                let ownRow = ownCell / columns
                let ownCol = ownCell % columns

                var candidates: Set<Int> = [ownCell]
                if ownCol > 0 { candidates.insert(ownRow * columns + (ownCol - 1)) }
                if ownCol < columns - 1 { candidates.insert(ownRow * columns + (ownCol + 1)) }
                if ownRow > 0 { candidates.insert((ownRow - 1) * columns + ownCol) }
                if ownRow < rows - 1 { candidates.insert((ownRow + 1) * columns + ownCol) }

                let normalizedImportance = importance.weight(x: x, y: y) / maxImportance
                let effectiveCompactness = max(1.0, compactness * (1.0 - 0.6 * normalizedImportance))

                let pixelColor = image.pixels[idx]
                var bestCell = ownCell
                var bestDistance = Double.greatestFiniteMagnitude

                for cell in candidates {
                    let colorDist = pixelColor.distance(to: cellColors[cell])
                    let dx = Double(x) - centers[cell].centerX
                    let dy = Double(y) - centers[cell].centerY
                    let spatialDist = (dx * dx + dy * dy).squareRoot()
                    let combined = (colorDist * colorDist) + pow(effectiveCompactness / spatialScale, 2) * (spatialDist * spatialDist)
                    if combined < bestDistance {
                        bestDistance = combined
                        bestCell = cell
                    }
                }
                newLabels[idx] = bestCell
            }
        }
        return newLabels
    }

    /// Runs the full iterative segmentation using raw (importance-weighted) Lab means,
    /// recomputed each iteration, until convergence or `iterations` is reached.
    public static func segment(
        image: PixelImage,
        columns: Int,
        rows: Int,
        importance: ImportanceMap,
        iterations: Int = 10,
        compactness: Double = 10.0
    ) -> SegmentationResult {
        var labels = initialLabels(width: image.width, height: image.height, columns: columns, rows: rows)
        var stats = cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: labels)

        for _ in 0..<iterations {
            let colors = stats.map(\.color)
            let newLabels = refine(
                image: image, columns: columns, rows: rows, importance: importance,
                labels: labels, cellColors: colors, centers: stats, compactness: compactness
            )
            if newLabels == labels {
                break
            }
            labels = newLabels
            stats = cellStats(image: image, columns: columns, rows: rows, importance: importance, labels: labels, fallback: stats)
        }
        return SegmentationResult(columns: columns, rows: rows, labels: labels)
    }
}
