import CoreGraphics
import Testing
@testable import BeadCore

@Suite("Source alpha cells")
struct SourceAlphaCellsTests {
    @Test func outsideAndEnclosedHole() {
        var a = [UInt8](repeating: 255, count: 25)
        for y in 0..<5 { for x in 0..<5 where x == 0 || x == 4 || y == 0 || y == 4 { a[y * 5 + x] = 0 } }
        a[2 * 5 + 2] = 0
        let fixed = SourceAlphaCells.classify(alpha: a, width: 5, height: 5, columns: 5, rows: 5)
        #expect(fixed[0] == .outside)
        #expect(fixed[4] == .outside)
        #expect(fixed[2 * 5 + 2] == .hole)
        #expect(fixed[2 * 5 + 1] == nil)
    }

    @Test func diagonalsDoNotConnectButOrthogonalPixelsDo() {
        var a = [UInt8](repeating: 255, count: 9)
        a[0] = 0
        a[4] = 0
        #expect(SourceAlphaCells.classify(alpha: a, width: 3, height: 3, columns: 3, rows: 3)[4] == .hole)
        a[1] = 0
        #expect(SourceAlphaCells.classify(alpha: a, width: 3, height: 3, columns: 3, rows: 3)[4] == .outside)
    }

    @Test func halfCoverageAndAlphaThreshold() {
        #expect(SourceAlphaCells.classify(alpha: [127, 128, 255, 255], width: 2, height: 2, columns: 1, rows: 1) == [nil])
        #expect(SourceAlphaCells.classify(alpha: [127, 128, 0, 255], width: 2, height: 2, columns: 1, rows: 1) == [.outside])
        #expect(SourceAlphaCells.classify(alpha: [0, 0, 0, 0], width: 2, height: 2, columns: 4, rows: 4).allSatisfy { $0 == .outside })
        #expect(SourceAlphaCells.classify(alpha: [255, 255, 255, 255], width: 2, height: 2, columns: 2, rows: 2).allSatisfy { $0 == nil })
    }

    @Test func cgImageAlphaTopRowMapsToFirstGridRow() {
        let space = CGColorSpaceCreateDeviceRGB()
        var rgba: [UInt8] = [0, 0, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255]
        let context = CGContext(data: &rgba, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let fixed = SourceAlphaCells.classify(source: context.makeImage()!, columns: 2, rows: 2)
        #expect(fixed == [.outside, nil, nil, nil])
    }
}
