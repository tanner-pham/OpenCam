import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct GradingTests {
    @Test func keysAndText() {
        #expect(AdjustmentKey.allCases.count == 49); #expect(EditorGroup.grading.keys.count == 11)
        #expect(EditorGroup.allCases.map(\.title) == ["Light", "Colour", "Curve", "Mix", "Grading", "Detail", "Effects", "Looks"])
        #expect(AdjustmentKey.gradingShadowsHue.range == 0...360); #expect(AdjustmentKey.gradingShadowsHue.valueText(210) == "210°")
        #expect(AdjustmentKey.gradingBlending.title == "Blending"); #expect(AdjustmentKey.gradingHighlightsLuminance.title == "Highlights luminance")
        #expect(GradingRegion.midtones.saturationKey == .gradingMidtonesSaturation) }
    @Test func wheelGeometry() {
        let d: CGFloat = 100; #expect(WheelGeometry.tint(at: CGPoint(x: 100, y: 50), diameter: d) == (0, 100))
        #expect(WheelGeometry.tint(at: CGPoint(x: 50, y: 100), diameter: d) == (90, 100))   // below the centre: clockwise
        #expect(WheelGeometry.tint(at: CGPoint(x: 0, y: 50), diameter: d) == (180, 100)); #expect(WheelGeometry.tint(at: CGPoint(x: 50, y: 0), diameter: d) == (270, 100))
        #expect(WheelGeometry.tint(at: CGPoint(x: 75, y: 50), diameter: d) == (0, 50)); #expect(WheelGeometry.tint(at: CGPoint(x: 200, y: 50), diameter: d) == (0, 100))
        #expect(WheelGeometry.tint(at: CGPoint(x: 50.1, y: 50.1), diameter: d) == (0, 0))   // saturation rounds to 0, so hue 0
        #expect(WheelGeometry.point(hue: 90, saturation: 50, diameter: d) == CGPoint(x: 50, y: 75))
        #expect(WheelGeometry.diameter(forWidth: 320) == 138); #expect(WheelGeometry.diameter(forWidth: 381) == 160) }
    @Test func stageNineRunsAfterSaturationAndBlendingAloneDoesNothing() {
        let toned = Adjustments().setting(.saturation, to: -100).setting(.gradingMidtonesHue, to: 30).setting(.gradingMidtonesSaturation, to: 50)
        let out = ColourMath.apply(toned, to: SIMD3(0.8, 0.4, 0.2)); #expect(out.x > out.z + 0.05)
        #expect(ColourMath.apply(Adjustments().setting(.gradingBlending, to: 80).setting(.gradingShadowsHue, to: 200), to: SIMD3(repeating: 0.5))
                == ColourMath.apply(Adjustments(), to: SIMD3(repeating: 0.5)))
        #expect(abs(ColourMath.apply(Adjustments().setting(.gradingMidtonesLuminance, to: 100), to: SIMD3(repeating: 0.5)).y - 0.7) < 1e-4) }
    @Test func resetWheelClearsHueAndSaturationOnly() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 64, height: 48)
        model.adjustments[.gradingShadowsHue] = 210; model.adjustments[.gradingShadowsSaturation] = 35; model.adjustments[.gradingShadowsLuminance] = -10; model.resetWheel(.shadows)
        #expect(model.adjustments[.gradingShadowsHue] == 0); #expect(model.adjustments[.gradingShadowsSaturation] == 0)
        #expect(model.adjustments[.gradingShadowsLuminance] == -10); #expect(LookSeeder.colourStudy[.gradingShadowsHue] == 210) }

    /// Stage 7 can leave a channel outside 0...1; grading weighs regions by luma, so it must read the clamped colour.
    /// Saturation 100 takes (0.95, 0.5, 0.95) to about (1.27, 0.37, 1.27): luma 0.63 unclamped, 0.55 clamped.
    @Test func stageNineGradesTheClampedColour() {
        let base = Adjustments().setting(.saturation, to: 100), input = SIMD3<Float>(0.95, 0.5, 0.95)
        let lifted = ColourMath.apply(base.setting(.gradingHighlightsLuminance, to: 100), to: input)
        let expected = ColourMath.grade(ColourMath.apply(base, to: input), shadows: .none, midtones: .none,
                                        highlights: ColourTint(hue: 0, saturation: 0, luminance: 1), balance: 0, blending: 0)
        #expect(abs(lifted.y - expected.y) < 1e-5) }

    /// Stage 9 runs on its own lanes: only a grading saturation or luminance turns it on, and the mixer's lanes never do.
    @Test func theGradingLanesFollowTheValues() throws {
        #expect(!Adjustments().hasGradingValues)
        for key in [AdjustmentKey.gradingShadowsHue, .gradingMidtonesHue, .gradingHighlightsHue, .gradingBlending, .gradingBalance] {
            #expect(!Adjustments().setting(key, to: 50).hasGradingValues, "\(key)") }
        for region in GradingRegion.allCases {
            #expect(Adjustments().setting(region.saturationKey, to: 35).hasGradingValues); #expect(Adjustments().setting(region.luminanceKey, to: -10).hasGradingValues) }
        let graded = Adjustments().setting(.gradingShadowsHue, to: 210).setting(.gradingShadowsSaturation, to: 35)
        #expect(!graded.hasMixerValues); #expect(!Adjustments().setting(.mixRedHue, to: 20).hasGradingValues)
        #expect(graded.setting(.gradingShadowsSaturation, to: 0).setting(.gradingShadowsHue, to: 0) == Adjustments())
        // Decoding goes through the same setter, so a decoded look grades as the one written.
        let decoded = try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(graded)); #expect(decoded == graded); #expect(decoded.hasGradingValues)
        let written = try JSONDecoder().decode([String: Double].self, from: JSONEncoder().encode(graded))
        #expect(written["gradingShadowsHue"] == 210); #expect(written["gradingMidtonesHue"] == nil); #expect(written.count == 16) }
}
