import Foundation

public enum PatternGridLayout {
    public static func groupPositions(cellCount: Int, cellSize: Double) -> [Double] {
        guard cellCount > 5, cellSize > 0 else { return [] }
        return stride(from: 5, to: cellCount, by: 5).map { Double($0) * cellSize }
    }

    public static func codeFontSize(cellSize: Double, codeLength: Int) -> Double? {
        guard cellSize >= 18, codeLength > 0 else { return nil }
        let size = min(14, min(cellSize * 0.38, (cellSize - 4) / (Double(codeLength) * 0.65)))
        return size >= 7 ? size : nil
    }
}
