import Testing
@testable import BeadCore

@Suite("Pattern grid layout")
struct PatternGridLayoutTests {
    @Test func interiorGroupBoundaries() {
        #expect(PatternGridLayout.groupPositions(cellCount: 12, cellSize: 10) == [50, 100])
        #expect(PatternGridLayout.groupPositions(cellCount: 4, cellSize: 10).isEmpty)
        #expect(PatternGridLayout.groupPositions(cellCount: 10, cellSize: 10) == [50])
    }

    @Test func labelsOnlyAtReadableSizes() {
        #expect(PatternGridLayout.codeFontSize(cellSize: 5, codeLength: 3) == nil)
        #expect(PatternGridLayout.codeFontSize(cellSize: 17, codeLength: 3) == nil)
        #expect(PatternGridLayout.codeFontSize(cellSize: 24, codeLength: 3) != nil)
        #expect(PatternGridLayout.codeFontSize(cellSize: 24, codeLength: 4) != nil)
    }
}
