import Testing
@testable import BeadCore

@Suite("ColorAttributes")
struct ColorAttributesTests {
    @Test("pure red converts to HSL hue 0, full saturation, 0.5 lightness")
    func pureRedHSL() {
        let hsl = HSLColor(red: 1, green: 0, blue: 0)
        #expect(abs(hsl.hue - 0) < 0.001)
        #expect(abs(hsl.saturation - 1.0) < 0.001)
        #expect(abs(hsl.lightness - 0.5) < 0.001)
    }

    @Test("pure white has zero saturation and lightness 1")
    func pureWhiteHSL() {
        let hsl = HSLColor(red: 1, green: 1, blue: 1)
        #expect(abs(hsl.saturation - 0.0) < 0.001)
        #expect(abs(hsl.lightness - 1.0) < 0.001)
    }

    @Test("pure black has zero saturation and lightness 0")
    func pureBlackHSL() {
        let hsl = HSLColor(red: 0, green: 0, blue: 0)
        #expect(abs(hsl.saturation - 0.0) < 0.001)
        #expect(abs(hsl.lightness - 0.0) < 0.001)
    }

    @Test("lightness >= 0.5 classifies as light")
    func lightnessClassBoundary() {
        #expect(HSLColor(hue: 0, saturation: 0.5, lightness: 0.5).lightnessClass == .light)
        #expect(HSLColor(hue: 0, saturation: 0.5, lightness: 0.499).lightnessClass == .dark)
    }

    @Test("low saturation below neutral threshold classifies as neutral")
    func neutralSaturationClass() {
        #expect(HSLColor(hue: 0, saturation: 0.05, lightness: 0.5).saturationClass == .neutral)
    }

    @Test("saturation at or above high threshold classifies as high")
    func highSaturationClass() {
        #expect(HSLColor(hue: 0, saturation: 0.35, lightness: 0.5).saturationClass == .high)
        #expect(HSLColor(hue: 0, saturation: 0.34, lightness: 0.5).saturationClass == .low)
    }

    @Test("hue distance wraps around the color circle")
    func hueDistanceWrapsAround() {
        let a = HSLColor(hue: 10, saturation: 0.5, lightness: 0.5)
        let b = HSLColor(hue: 350, saturation: 0.5, lightness: 0.5)
        #expect(abs(a.hueDistance(to: b) - 20) < 0.001)
    }

    @Test("hue distance for opposite hues is 180")
    func hueDistanceForComplementary() {
        let a = HSLColor(hue: 0, saturation: 0.5, lightness: 0.5)
        let b = HSLColor(hue: 180, saturation: 0.5, lightness: 0.5)
        #expect(abs(a.hueDistance(to: b) - 180) < 0.001)
    }

    @Test("MardColor.hsl matches direct HSLColor conversion from its RGB")
    func mardColorHSLMatchesDirectConversion() {
        let color = MardColor(code: "TEST", hex: "01ACEB")
        let direct = HSLColor(red: color.red, green: color.green, blue: color.blue)
        #expect(abs(color.hsl.hue - direct.hue) < 0.001)
        #expect(abs(color.hsl.saturation - direct.saturation) < 0.001)
        #expect(abs(color.hsl.lightness - direct.lightness) < 0.001)
    }
}
