import Foundation
import Testing
@testable import OpenCam

@Suite struct ColourMathTests {
    let grey = SIMD3<Float>(repeating: 0.5)
    func apply(_ key: AdjustmentKey, _ value: Double, _ rgb: SIMD3<Float>) -> SIMD3<Float> { ColourMath.apply(Adjustments().setting(key, to: value), to: rgb) }
    func maxDiff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }

    @Test func zeroAdjustmentsReturnTheInput() {
        for rgb in [SIMD3<Float>(0, 0, 0), SIMD3(1, 1, 1), SIMD3(0.2, 0.5, 0.8), SIMD3(0.03, 0.9, 0.4)] {
            #expect(maxDiff(ColourMath.apply(Adjustments(), to: rgb), rgb) < 1e-5)
        }
    }
    @Test func plusOneStopDoublesLinearMidGrey() {
        let out = apply(.exposure, 1, grey)
        #expect(abs(ColourMath.decode(out.x) - 2 * ColourMath.decode(0.5)) < 1e-4); #expect(abs(out.x - 0.68584) < 1e-4)
    }
    @Test func saturationMinus100GivesRec709Luma() {
        let out = apply(.saturation, -100, SIMD3(0.8, 0.4, 0.2))
        #expect(abs(out.x - 0.4706) < 1e-4); #expect(abs(out.x - out.y) < 1e-6); #expect(abs(out.y - out.z) < 1e-6)
    }
    @Test func positiveTemperatureRaisesRedAndLowersBlue() {
        let out = apply(.temperature, 50, grey)
        #expect(out.x > 0.51); #expect(out.z < 0.49); #expect(abs(out.y - 0.5) < 1e-5)
    }
    @Test func highlightsAndShadowsKeepBlackAndWhite() {
        for key in [AdjustmentKey.highlights, .shadows] {
            for value in [-100.0, 100] {
                #expect(maxDiff(apply(key, value, .zero), .zero) < 1e-6); #expect(maxDiff(apply(key, value, .one), .one) < 1e-5)
            }
        }
    }
    @Test(arguments: [
        Probe(key: .exposure, rgb: SIMD3(repeating: 0.4), channel: 0, rises: true), Probe(key: .contrast, rgb: SIMD3(repeating: 0.75), channel: 0, rises: true),
        Probe(key: .highlights, rgb: SIMD3(repeating: 0.8), channel: 0, rises: true), Probe(key: .shadows, rgb: SIMD3(repeating: 0.2), channel: 0, rises: true),
        Probe(key: .whites, rgb: SIMD3(repeating: 0.8), channel: 0, rises: true), Probe(key: .blacks, rgb: SIMD3(repeating: 0.1), channel: 0, rises: true),
        Probe(key: .temperature, rgb: SIMD3(repeating: 0.5), channel: 0, rises: true), Probe(key: .temperature, rgb: SIMD3(repeating: 0.5), channel: 2, rises: false),
        Probe(key: .tint, rgb: SIMD3(repeating: 0.5), channel: 1, rises: false), Probe(key: .vibrance, rgb: SIMD3(0.7, 0.5, 0.4), channel: 0, rises: true),
        Probe(key: .saturation, rgb: SIMD3(0.7, 0.5, 0.4), channel: 0, rises: true),
    ])
    func everySliderIsMonotonic(_ probe: Probe) throws {
        let range = probe.key.range
        let values = stride(from: range.lowerBound, through: range.upperBound, by: (range.upperBound - range.lowerBound) / 40)
            .map { apply(probe.key, $0, probe.rgb)[probe.channel] }
        for (a, b) in zip(values, values.dropFirst()) { #expect(probe.rises ? b >= a - 1e-6 : b <= a + 1e-6) }
        let first = try #require(values.first), last = try #require(values.last)
        #expect(abs(last - first) > 0.05)   // the slider does something
    }
    /// Pins the stage order: exposure (stage 1) before contrast (3) before saturation (7).
    /// Expected values worked out by hand in that order: (0.6, 0.4, 0.3) +0.5 stop gives (0.70176, 0.47069, 0.35515),
    /// contrast +30 about 0.5 gives (0.76228, 0.46189, 0.31170), saturation +40 about its luma 0.51491 gives (0.86123, 0.44068, 0.23041).
    @Test func severalStagesApplyInTheFixedOrder() {
        let rgb = SIMD3<Float>(0.6, 0.4, 0.3)
        let all = Adjustments().setting(.exposure, to: 0.5).setting(.contrast, to: 30).setting(.saturation, to: 40)
        let out = ColourMath.apply(all, to: rgb)
        #expect(maxDiff(out, SIMD3(0.86123, 0.44068, 0.23041)) < 1e-4)
        // Contrast and saturation commute (both scale about a point), so a reordering that matters moves exposure.
        let reordered = apply(.exposure, 0.5, apply(.contrast, 30, apply(.saturation, 40, rgb)))
        #expect(maxDiff(reordered, out) > 0.02)
    }
    @Test func e1TablesAreRebuiltBitForBit() {   // Review Focus 2
        for a in [Adjustments(), LookSeeder.warmFade, Adjustments().setting(.contrast, to: 60).setting(.tint, to: -30)] {
            var expected = [Float]()   // LookCompiler's order: red fastest, then green, then blue; alpha 1
            for b in 0..<33 { for g in 0..<33 { for r in 0..<33 {
                let out = E1ColourReference.apply(a, to: SIMD3(Float(r) / 32, Float(g) / 32, Float(b) / 32)); expected += [out.x, out.y, out.z, 1]
            } } }
            #expect(LookCompiler.cube(for: a).data == expected)
        }
    }
    @Test func masterRunsBeforeTheChannelCurve() {
        var a = Adjustments(); a.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 1, y: 1)])
        #expect(maxDiff(ColourMath.apply(a, to: grey), SIMD3(0.6, 0.6, 0.6)) < 1e-4); a.curves.red = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.7), CurvePoint(x: 1, y: 1)])
        #expect(maxDiff(ColourMath.apply(a, to: grey), SIMD3(0.77536, 0.6, 0.6)) < 1e-4)   // red curve at 0.6
    }
}
