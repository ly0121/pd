import CoreGraphics
import CoreVideo
import Foundation
import Vision

public protocol ForegroundMaskProvider: Sendable {
    /// Returns one foreground-probability weight per pixel in [0, 1], row-major matching
    /// `image`'s dimensions, or nil if no background removal should happen (e.g. the caller
    /// didn't request it, or detection found nothing to work with).
    func foregroundMask(for image: CGImage) -> [Double]?
}

/// Default provider for when background removal isn't requested — always returns nil, so
/// `PatternGenerator` treats every cell as foreground and nothing changes from today's behavior.
public struct UniformForegroundMaskProvider: ForegroundMaskProvider {
    public init() {}

    public func foregroundMask(for image: CGImage) -> [Double]? { nil }
}

/// Detects the photo's main subject(s) via Vision's foreground instance segmentation and
/// produces a per-pixel foreground-probability map. Falls back to nil (no background removal)
/// whenever Vision can't produce a usable mask — a missed detection should never accidentally
/// blank out the entire image.
public struct VisionForegroundMaskProvider: ForegroundMaskProvider {
    public init() {}

    public func foregroundMask(for image: CGImage) -> [Double]? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                return nil
            }
            let pixelBuffer = try observation.generateScaledMaskForImage(
                forInstances: observation.allInstances, from: handler
            )
            return Self.resampleMask(from: pixelBuffer, to: image.width, height: image.height)
        } catch {
            return nil
        }
    }

    /// Nearest-neighbor resamples an 8-bit single-channel mask buffer (Vision's foreground
    /// instance mask output format) up to the target width/height, normalizing byte values
    /// [0, 255] into [0.0, 1.0].
    static func resampleMask(from pixelBuffer: CVPixelBuffer, to targetWidth: Int, height targetHeight: Int) -> [Double]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let byteBuffer = base.assumingMemoryBound(to: UInt8.self)

        var weights = [Double](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let sourceY = min(sourceHeight - 1, (y * sourceHeight) / targetHeight)
            for x in 0..<targetWidth {
                let sourceX = min(sourceWidth - 1, (x * sourceWidth) / targetWidth)
                let raw = byteBuffer[sourceY * bytesPerRow + sourceX]
                weights[y * targetWidth + x] = Double(raw) / 255.0
            }
        }
        return weights
    }
}
