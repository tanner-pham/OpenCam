import Foundation
import Testing
@testable import OpenCam

@Suite struct AdjustmentsTests {
    @Test func defaultsAreIdentityAndRoundTrip() throws {
        #expect(Adjustments().isIdentity); #expect(!Adjustments().hasColourChanges)
        let a = Adjustments().setting(.exposure, to: 1.5).setting(.grain, to: 30).setting(.tint, to: -12)
        #expect(!a.isIdentity); #expect(a.hasColourChanges); #expect(!Adjustments().setting(.grain, to: 30).hasColourChanges)
        #expect(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)) == a)
    }
    @Test func decodingToleratesMissingAndUnknownKeysAndClamps() throws {
        let json = #"{"exposure": 9, "contrast": -250, "saturation": 40, "toneCurve": [0, 1]}"#
        let a = try JSONDecoder().decode(Adjustments.self, from: Data(json.utf8))
        #expect(a.exposure == 5); #expect(a.contrast == -100); #expect(a.saturation == 40); #expect(a.shadows == 0); #expect(a.grain == 0)
    }
    @Test func keysCarryTitlesRangesGroupsAndText() {
        #expect(AdjustmentKey.allCases.map(\.title) == ["Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks", "Temperature", "Tint",
                                                         "Vibrance", "Saturation", "Sharpening", "Noise reduction", "Grain", "Vignette"])
        #expect(AdjustmentKey.exposure.range == -5...5); #expect(AdjustmentKey.grain.range == 0...100); #expect(AdjustmentKey.vignette.range == -100...100)
        #expect(EditorGroup.light.keys == [.exposure, .contrast, .highlights, .shadows, .whites, .blacks])
        #expect(EditorGroup.colour.keys == [.temperature, .tint, .vibrance, .saturation])
        #expect(EditorGroup.detail.keys == [.sharpening, .noiseReduction]); #expect(EditorGroup.effects.keys == [.grain, .vignette])
        #expect(EditorGroup.looks.keys.isEmpty); #expect(EditorGroup.allCases.map(\.title) == ["Light", "Colour", "Detail", "Effects", "Looks"])
        #expect(AdjustmentKey.exposure.valueText(0.5) == "+0.5"); #expect(AdjustmentKey.exposure.valueText(0) == "0.0")
        #expect(AdjustmentKey.exposure.valueText(-1.3) == "-1.3")
        #expect(AdjustmentKey.contrast.valueText(-35) == "-35"); #expect(AdjustmentKey.contrast.valueText(20) == "+20"); #expect(AdjustmentKey.grain.valueText(20) == "20")
        #expect(AdjustmentKey.contrast.valueText(0) == "0")
        #expect(Adjustments().setting(.exposure, to: 8).exposure == 5)
    }
}
