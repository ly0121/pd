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

        // A bright line is not evidence for forcing a dark bead, even at maximum contrast.
        #expect(lightLineWeight < 0.18)
    }

    @Test("smooth Lab ramps never reach dark-outline forcing strength")
    func smoothRampsAreNotDarkContours() {
        for width in [192, 600] {
            let pixels = (0..<width * 3).map { index in
                LabColor(l: 30 + 50 * Double(index % width) / Double(width - 1), a: 0, b: 0)
            }
            let image = PixelImage(width: width, height: 3, pixels: pixels)
            #expect(ContourDetector.detect(image).allSatisfy { $0 < 0.18 })
        }
    }

    @Test("light sides of a sharp boundary are not dark contours")
    func lightBoundaryIsNotForcedDark() {
        let pixels = (0..<64).map { index in
            LabColor(l: index % 8 < 4 ? 10 : 90, a: 0, b: 0)
        }
        let weights = ContourDetector.detect(PixelImage(width: 8, height: 8, pixels: pixels))
        #expect(weights[3 * 8 + 3] > 0.18)
        #expect(weights[3 * 8 + 4] == 0)
    }

    @Test("representable midgray edges are not darkened")
    func midgrayEdgesAreNotDarkOutlines() {
        let gray = MardPalette.standard221.first { $0.code == "H4" }!
        let white = MardPalette.standard221.first { $0.code == "H2" }!
        let pixels = (0..<64).map { index in (index % 8 < 4 ? gray : white).lab }
        let weights = ContourDetector.detect(PixelImage(width: 8, height: 8, pixels: pixels))
        #expect(weights.allSatisfy { $0 < 0.18 })
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
