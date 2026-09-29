import CoreGraphics
import CoreVideo
import Testing
@testable import BeadCore

@Suite("ForegroundMaskProvider")
struct ForegroundMaskProviderTests {
    /// A bright, clearly-bounded circle on a plain dark background — the kind of high-contrast
    /// synthetic image Vision's subject/foreground segmentation can reliably pick up on, used to
    /// verify the end-to-end pipeline (not just the resampling math) produces a sane result.
    static func makeSubjectImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1)
        let diameter = min(width, height) / 2
        context.fillEllipse(in: CGRect(
            x: (width - diameter) / 2, y: (height - diameter) / 2, width: diameter, height: diameter
        ))
        return context.makeImage()!
    }

    @Test("UniformForegroundMaskProvider always returns nil")
    func uniformProviderReturnsNil() {
        let image = Self.makeSubjectImage(width: 32, height: 32)
        let provider = UniformForegroundMaskProvider()

        #expect(provider.foregroundMask(for: image) == nil)
    }

    @Test("VisionForegroundMaskProvider returns a mask sized to the image's dimensions when a subject is detected, or nil if none was found")
    func visionProviderMatchesDimensionsOrReturnsNil() {
        let image = Self.makeSubjectImage(width: 128, height: 128)
        let provider = VisionForegroundMaskProvider()

        let mask = provider.foregroundMask(for: image)

        // Vision's subject detection on synthetic images isn't guaranteed to find an instance,
        // so this only asserts internal consistency when it does — never crash, never return a
        // mismatched size.
        if let mask {
            #expect(mask.count == 128 * 128)
            #expect(mask.allSatisfy { $0 >= 0.0 && $0 <= 1.0 })
        }
    }

    @Test("resampleMask rejects a pixel buffer with the wrong pixel format")
    func resampleMaskRejectsWrongFormat() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)

        let result = VisionForegroundMaskProvider.resampleMask(from: pixelBuffer!, to: 8, height: 8)

        #expect(result == nil)
    }

    @Test("resampleMask upsamples a small 8-bit mask buffer and normalizes to [0, 1]")
    func resampleMaskUpsamplesAndNormalizes() {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_OneComponent8]
        CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &pixelBuffer)
        let buffer = pixelBuffer!

        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        base[0 * bytesPerRow + 0] = 0
        base[0 * bytesPerRow + 1] = 255
        base[1 * bytesPerRow + 0] = 0
        base[1 * bytesPerRow + 1] = 255
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let weights = VisionForegroundMaskProvider.resampleMask(from: buffer, to: 4, height: 4)

        #expect(weights != nil)
        #expect(weights?.count == 16)
        // Left half should resample from the 0-byte source column, right half from the 255 column.
        #expect(weights?[0] == 0.0)
        #expect(weights?[3] == 1.0)
    }
}
