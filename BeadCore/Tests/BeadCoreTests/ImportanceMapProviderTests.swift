import CoreGraphics
import CoreVideo
import Testing
@testable import BeadCore

@Suite("ImportanceMapProvider")
struct ImportanceMapProviderTests {
    /// Builds a simple synthetic CGImage: a bright square centered in an otherwise dark canvas,
    /// which should register as more "salient" than the uniform background.
    static func makeTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.95, green: 0.9, blue: 0.2, alpha: 1)
        let squareSize = min(width, height) / 3
        context.fill(CGRect(
            x: (width - squareSize) / 2, y: (height - squareSize) / 2,
            width: squareSize, height: squareSize
        ))
        return context.makeImage()!
    }

    @Test("uniform provider returns a flat weight map matching image dimensions")
    func uniformProviderIsFlat() {
        let image = Self.makeTestImage(width: 16, height: 12)
        let provider = UniformImportanceMapProvider()

        let map = provider.importanceMap(for: image)

        #expect(map.width == 16)
        #expect(map.height == 12)
        #expect(map.weights.allSatisfy { $0 == 1.0 })
    }

    @Test("vision saliency provider produces a weight map matching image dimensions")
    func visionProviderMatchesDimensions() {
        let image = Self.makeTestImage(width: 64, height: 64)
        let provider = VisionSaliencyImportanceMapProvider()

        let map = provider.importanceMap(for: image)

        #expect(map.width == 64)
        #expect(map.height == 64)
    }

    @Test("vision saliency provider normalizes weights into [0, 1]")
    func visionProviderNormalizesWeights() {
        let image = Self.makeTestImage(width: 64, height: 64)
        let provider = VisionSaliencyImportanceMapProvider()

        let map = provider.importanceMap(for: image)

        #expect(map.weights.allSatisfy { $0 >= 0.0 && $0 <= 1.0 })
        // A real saliency result should have some variation, not be perfectly flat.
        let distinctValues = Set(map.weights.map { ($0 * 1000).rounded() })
        #expect(distinctValues.count > 1)
    }

    @Test("resampleWeights rejects a pixel buffer with the wrong pixel format")
    func resampleWeightsRejectsWrongFormat() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)

        let result = VisionSaliencyImportanceMapProvider.resampleWeights(from: pixelBuffer!, to: 8, height: 8)

        #expect(result == nil)
    }

    @Test("resampleWeights upsamples a small buffer to a larger target size")
    func resampleWeightsUpsamples() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_OneComponent32Float]
        CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_OneComponent32Float, attrs as CFDictionary, &pixelBuffer)
        let buffer = pixelBuffer!

        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.size
        base[0 * floatsPerRow + 0] = 0.0
        base[0 * floatsPerRow + 1] = 1.0
        base[1 * floatsPerRow + 0] = 0.0
        base[1 * floatsPerRow + 1] = 1.0
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let weights = VisionSaliencyImportanceMapProvider.resampleWeights(from: buffer, to: 4, height: 4)

        #expect(weights != nil)
        #expect(weights?.count == 16)
        // Left half should resample from the 0.0 source column, right half from the 1.0 column.
        #expect(weights?[0] == 0.0)
        #expect(weights?[3] == 1.0)
    }
}
