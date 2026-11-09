import BeadCore
import CoreGraphics
import Photos
import XCTest
@testable import PerlerBeadApp

final class PatternExportRendererTests: XCTestCase {
    func testEmptyCellsRemainTransparentExceptAtFiveCellDividers() throws {
        let blue = MardPalette.allColors.first { $0.code == "C6" }!
        var colors = [MardColor](repeating: blue, count: 12 * 12)
        // Cover both top-left UIKit and bottom-left Core Graphics row origins.
        for row in 4...7 {
            for col in 4...6 {
                colors[row * 12 + col] = .empty
            }
        }
        let grid = BeadGrid(columns: 12, rows: 12, colors: colors)
        let image = PatternExportRenderer.render(grid)
        let cgImage = try XCTUnwrap(image.cgImage)
        let pixels = try XCTUnwrap(cgImage.dataProvider?.data as Data?)
        XCTAssertGreaterThan(pixels.count, 0)

        let center = CGPoint(x: 28 + 4 * 24 + 12, y: 28 + 4 * 24 + 12)
        let divider = CGPoint(x: 28 + 5 * 24, y: center.y)
        XCTAssertEqual(try alpha(at: center, scale: image.scale, in: cgImage), 0)
        XCTAssertGreaterThan(try alpha(at: divider, scale: image.scale, in: cgImage), 0)
        XCTAssertEqual(try alpha(at: CGPoint(x: 28 + 2 * 24 + 12, y: center.y), scale: image.scale, in: cgImage), 255)
    }

    func testPNGResourceSaveSupportsTransparentGrid() throws {
        let blue = MardPalette.allColors.first { $0.code == "C6" }!
        var colors = [MardColor](repeating: blue, count: 12 * 12)
        for row in 4...7 {
            for col in 4...6 { colors[row * 12 + col] = .empty }
        }
        let image = PatternExportRenderer.render(BeadGrid(columns: 12, rows: 12, colors: colors))
        let pngData = try XCTUnwrap(image.pngData())
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try pngData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let png = try XCTUnwrap(UIImage(contentsOfFile: fileURL.path))
        let bitmap = try XCTUnwrap(png.cgImage)
        let center = CGPoint(x: 28 + 4 * 24 + 12, y: 28 + 4 * 24 + 12)
        XCTAssertEqual(try alpha(at: center, scale: image.scale, in: bitmap), 0)
        XCTAssertGreaterThan(try alpha(at: CGPoint(x: 28 + 5 * 24, y: center.y), scale: image.scale, in: bitmap), 0)

        let saved = expectation(description: "Photo saved")
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: fileURL, options: nil)
        }) { success, error in
            XCTAssertTrue(success, "\(String(describing: error))")
            saved.fulfill()
        }
        wait(for: [saved], timeout: 30)
    }

    private func alpha(at point: CGPoint, scale: CGFloat, in image: CGImage) throws -> UInt8 {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes[(Int(point.y * scale) * width + Int(point.x * scale)) * 4 + 3]
    }
}
