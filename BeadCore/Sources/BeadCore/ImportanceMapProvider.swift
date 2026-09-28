import CoreGraphics
import CoreVideo
import Foundation
import Vision

public protocol ImportanceMapProvider: Sendable {
    func importanceMap(for image: CGImage) -> ImportanceMap
}

public struct UniformImportanceMapProvider: ImportanceMapProvider {
    public init() {}

    public func importanceMap(for image: CGImage) -> ImportanceMap {
        ImportanceMap.uniform(width: image.width, height: image.height)
    }
}

/// Generates a per-pixel importance map from Vision's attention-based saliency detection.
/// Falls back to a uniform map when Vision fails to produce a usable observation (e.g. request
/// error, or an image Vision can't process), so callers never need to special-case failure.
public struct VisionSaliencyImportanceMapProvider: ImportanceMapProvider {
    public init() {}

    public func importanceMap(for image: CGImage) -> ImportanceMap {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  let weights = Self.resampleWeights(from: observation.pixelBuffer, to: image.width, height: image.height)
            else {
                return .uniform(width: image.width, height: image.height)
            }
            return ImportanceMap(width: image.width, height: image.height, weights: weights)
        } catch {
            return .uniform(width: image.width, height: image.height)
        }
    }

    /// Nearest-neighbor resamples a single-channel float32 CVPixelBuffer (Vision's saliency
    /// output resolution) up to the target width/height, normalizing values to [0, 1].
    static func resampleWeights(from pixelBuffer: CVPixelBuffer, to targetWidth: Int, height targetHeight: Int) -> [Double]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent32Float else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let floatBuffer = base.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

        var minValue = Float32.greatestFiniteMagnitude
        var maxValue = -Float32.greatestFiniteMagnitude
        for y in 0..<sourceHeight {
            for x in 0..<sourceWidth {
                let value = floatBuffer[y * floatsPerRow + x]
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }
        }
        let range = max(maxValue - minValue, 0.0001)

        var weights = [Double](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let sourceY = min(sourceHeight - 1, (y * sourceHeight) / targetHeight)
            for x in 0..<targetWidth {
                let sourceX = min(sourceWidth - 1, (x * sourceWidth) / targetWidth)
                let raw = floatBuffer[sourceY * floatsPerRow + sourceX]
                weights[y * targetWidth + x] = Double((raw - minValue) / range)
            }
        }
        return weights
    }
}
