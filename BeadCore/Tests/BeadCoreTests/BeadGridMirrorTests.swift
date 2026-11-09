import Testing
@testable import BeadCore

@Suite("BeadGrid mirror")
struct BeadGridMirrorTests {
    @Test func reversesEachRowIncludingEmptyCells() {
        let a = MardColor(code: "A1", hex: "000000")
        let b = MardColor(code: "A2", hex: "FFFFFF")
        let grid = BeadGrid(columns: 3, rows: 2, colors: [a, b, .empty, b, a, b])
        let mirrored = grid.mirroredHorizontally()
        #expect(mirrored.colors == [.empty, b, a, b, a, b])
        #expect(mirrored.mirroredHorizontally() == grid)
    }
}
