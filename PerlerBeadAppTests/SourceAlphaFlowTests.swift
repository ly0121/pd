import BeadCore
import CoreGraphics
import XCTest
@testable import PerlerBeadApp

@MainActor
final class SourceAlphaFlowTests: XCTestCase {
    func testRotatedSourceKeepsAlphaAlignedWithVisiblePixels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
            context.cgContext.clear(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let rotated = UIImage(cgImage: try XCTUnwrap(upright.cgImage), scale: 1, orientation: .right)
        let normalized = NewProjectFlowModel.normalizedForGeneration(rotated)
        let reduced = try XCTUnwrap(NewProjectFlowModel.downsample(normalized, targetColumns: 3, pixelsPerCell: 2))
        let grid = PatternGenerator.generate(
            cgImage: try XCTUnwrap(reduced.cgImage),
            importanceProvider: UniformImportanceMapProvider(),
            options: PatternGenerationOptions(columns: 3, rows: 3, palette: [MardPalette.allColors.first { $0.code == "F3" }!]),
            sourceAlphaImage: try XCTUnwrap(normalized.cgImage)
        )
        XCTAssertEqual(normalized.imageOrientation, .up)
        XCTAssertEqual(grid.color(col: 2, row: 0), .empty)
        XCTAssertNotEqual(grid.color(col: 0, row: 0), .empty)
        let restored = try XCTUnwrap(UIImage(data: XCTUnwrap(normalized.pngData())))
        XCTAssertEqual(SourceAlphaCells.classify(source: try XCTUnwrap(restored.cgImage), columns: 3, rows: 3),
                       SourceAlphaCells.classify(source: try XCTUnwrap(normalized.cgImage), columns: 3, rows: 3))
    }

    func testDownsampledImageUsesSourceTransparencyAndSavedSourceRegenerates() throws {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60), format: format).image { context in
            UIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1).setFill()
            context.fill(CGRect(x: 12, y: 12, width: 36, height: 36))
            context.cgContext.clear(CGRect(x: 24, y: 24, width: 12, height: 12))
        }
        let h1 = try XCTUnwrap(MardPalette.allColors.first { $0.code == "H1" })
        let c6 = try XCTUnwrap(MardPalette.allColors.first { $0.code == "C6" })
        func generate(_ source: UIImage, size: Int, palette: [MardColor]) throws -> BeadGrid {
            let reduced = try XCTUnwrap(NewProjectFlowModel.downsample(source, targetColumns: size, pixelsPerCell: 2))
            return PatternGenerator.generate(
                cgImage: try XCTUnwrap(reduced.cgImage),
                importanceProvider: UniformImportanceMapProvider(),
                options: PatternGenerationOptions(columns: size, rows: size, palette: palette),
                sourceAlphaImage: try XCTUnwrap(source.cgImage)
            )
        }
        let initial = try generate(image, size: 5, palette: [h1, c6])
        XCTAssertEqual(initial.color(col: 0, row: 0), .empty)
        XCTAssertEqual(initial.color(col: 2, row: 2), h1)
        let restored = try XCTUnwrap(UIImage(data: XCTUnwrap(image.pngData())))
        let resized = try generate(restored, size: 10, palette: [c6])
        XCTAssertEqual(resized.color(col: 0, row: 0), .empty)
        XCTAssertEqual(resized.color(col: 4, row: 4), .empty)
    }
}
