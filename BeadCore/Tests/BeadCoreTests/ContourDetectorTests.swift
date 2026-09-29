import Testing
@testable import BeadCore

@Suite("ContourDetector")
struct ContourDetectorTests {
    @Test("flat uniform image produces zero contour weight everywhere")
    func flatImageHasNoContours() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 6, height: 6, pixels: [LabColor](repeating: gray, count: 36))

        let weights = ContourDetector.detect(image)

        #expect(weights.allSatisfy { $0 == 0 })
    }

    @Test("a dark vertical line on a light background produces high weight at the line, low elsewhere")
    func darkLineOnLightBackgroundIsDetected() {
        let light = LabColor(l: 90, a: 0, b: 0)
        let dark = LabColor(l: 10, a: 0, b: 0)
        var pixels = [LabColor](repeating: light, count: 8 * 8)
        for y in 0..<8 {
            pixels[y * 8 + 4] = dark
        }
        let image = PixelImage(width: 8, height: 8, pixels: pixels)

        let weights = ContourDetector.detect(image)

        let lineWeight = weights[3 * 8 + 4]
        let backgroundWeight = weights[3 * 8 + 0]
        #expect(lineWeight > 0.3)
        #expect(backgroundWeight < lineWeight)
    }

    @Test("a light line on a dark background is damped relative to an equally strong dark line")
    func lightLineOnDarkBackgroundIsDamped() {
        let dark = LabColor(l: 10, a: 0, b: 0)
        let light = LabColor(l: 90, a: 0, b: 0)
        var pixels = [LabColor](repeating: dark, count: 8 * 8)
        for y in 0..<8 {
            pixels[y * 8 + 4] = light
        }
        let image = PixelImage(width: 8, height: 8, pixels: pixels)

        let weights = ContourDetector.detect(image)
        let lightLineWeight = weights[3 * 8 + 4]

        // Same edge magnitude as the dark-line-on-light-background case, but the line pixel
        // itself is NOT darker than its neighborhood, so it should be strongly damped.
        #expect(lightLineWeight < 0.35)
    }

    @Test("output has one weight per pixel, all within [0, 1]")
    func outputDimensionsAndRangeAreValid() {
        let gray = LabColor(l: 50, a: 5, b: -5)
        var pixels = [LabColor](repeating: gray, count: 5 * 5)
        pixels[12] = LabColor(l: 5, a: 0, b: 0)
        let image = PixelImage(width: 5, height: 5, pixels: pixels)

        let weights = ContourDetector.detect(image)

        #expect(weights.count == 25)
        #expect(weights.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test("edge pixels at the image boundary do not crash and produce finite weights")
    func boundaryPixelsAreHandledSafely() {
        let gray = LabColor(l: 50, a: 0, b: 0)
        let image = PixelImage(width: 2, height: 2, pixels: [LabColor](repeating: gray, count: 4))

        let weights = ContourDetector.detect(image)

        #expect(weights.count == 4)
        #expect(weights.allSatisfy { $0.isFinite })
    }
}
