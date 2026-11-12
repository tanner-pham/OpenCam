import Foundation
import Testing
@testable import OpenCam

@Suite struct ColourToolMathTests {
    let red = SIMD3<Float>(0.75, 0.25, 0.25), blue = SIMD3<Float>(0.25, 0.25, 0.75), green = SIMD3<Float>(0.25, 0.75, 0.25)
    let grey = SIMD3<Float>(repeating: 0.5), zero8 = SIMD8<Float>(repeating: 0)
    func maxDiff(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).squareRoot().max() }
    func only(_ band: ColourBand, _ v: Float) -> SIMD8<Float> { var s = SIMD8<Float>(repeating: 0); s[band.index] = v; return s }
    func mix(_ x: SIMD3<Float>, hue: SIMD8<Float>? = nil, sat: SIMD8<Float>? = nil, lum: SIMD8<Float>? = nil) -> SIMD3<Float> {
        ColourMath.mix(x, hue: hue ?? zero8, saturation: sat ?? zero8, luminance: lum ?? zero8) }
    func grade(_ x: SIMD3<Float>, s: ColourTint = .none, m: ColourTint = .none, h: ColourTint = .none, balance: Float = 0, blending: Float = 0) -> SIMD3<Float> {
        ColourMath.grade(x, shadows: s, midtones: m, highlights: h, balance: balance, blending: blending) }
    @Test func hsvBandsAndWeights() {
        #expect(maxDiff(ColourMath.hsv(red), SIMD3(0, 2.0 / 3, 0.75)) < 1e-6); #expect(maxDiff(ColourMath.hsv(grey), SIMD3(0, 0, 0.5)) < 1e-6)
        #expect(maxDiff(ColourMath.rgb(hue: 30, saturation: 2.0 / 3, value: 0.75), SIMD3(0.75, 0.5, 0.25)) < 1e-6)
        #expect(ColourBand.allCases.map(\.centre) == [0, 30, 60, 120, 180, 240, 270, 300]); #expect(ColourMath.bandWeights(hue: 15) == only(.red, 0.5) + only(.orange, 0.5))
        #expect(ColourMath.bandWeights(hue: 330) == only(.magenta, 0.5) + only(.red, 0.5))
        for tenth in 0..<3600 {
            let w = ColourMath.bandWeights(hue: Float(tenth) / 10); #expect(abs(w.sum() - 1) < 1e-5); #expect((0..<8).filter { w[$0] > 0 }.count <= 2) } }
    @Test func mixerIsIdentityAtZeroAndStaysInItsBand() {
        for x in [red, blue, green, grey, SIMD3(0.03, 0.9, 0.4), .zero, .one] { #expect(maxDiff(mix(x), x) < 1e-5) }
        #expect(maxDiff(mix(red, hue: only(.red, 1)), SIMD3(0.75, 0.5, 0.25)) < 1e-5); #expect(maxDiff(mix(SIMD3(0.75, 0.375, 0.25), hue: only(.red, 1)), SIMD3(0.75, 0.5, 0.25)) < 1e-5)
        #expect(maxDiff(mix(blue, hue: only(.red, 1)), blue) < 1e-6); #expect(maxDiff(mix(blue, hue: only(.purple, 1)), blue) < 1e-6)
        #expect(maxDiff(mix(red, sat: only(.red, -1)), SIMD3(0.75, 0.75, 0.75)) < 1e-5); #expect(maxDiff(mix(red, lum: only(.red, -1)), SIMD3(0.5, 1.0 / 6, 1.0 / 6)) < 1e-5)
        let all = SIMD8<Float>(repeating: 1); #expect(maxDiff(mix(grey, hue: all, sat: all, lum: all), grey) < 1e-6) }
    @Test func gradingAtZeroIsTheIdentityAndRegionsKeepTheirEnds() {
        for hue: Float in [0, 90, 200, 330] { for b: Float in [-1, 0, 1] { for x in [red, grey, .zero, .one] {
            let t = ColourTint(hue: hue, saturation: 0); #expect(grade(x, s: t, m: t, h: t, balance: b, blending: b) == x) } } }
        for b: Float in [-1, 0, 1] {
            #expect(grade(.one, s: ColourTint(hue: 220, saturation: 1, luminance: -1), balance: b, blending: b) == .one)
            #expect(grade(.zero, h: ColourTint(hue: 40, saturation: 1, luminance: 1), balance: b, blending: b) == .zero) } }
    @Test func midtonesTintKeepsLumaAndLuminanceLifts() {
        let tinted = grade(grey, m: ColourTint(hue: 0, saturation: 1)); #expect(maxDiff(tinted, SIMD3(0.69685, 0.44685, 0.44685)) < 1e-4); #expect(abs(ColourMath.luma(tinted) - 0.5) < 1e-5)
        #expect(maxDiff(grade(grey, m: ColourTint(hue: 0, saturation: 0, luminance: 1)), SIMD3(repeating: 0.7)) < 1e-5) }
    @Test func balanceAndBlendingMoveTheSplit() {
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.5, balance: 0, blending: 0), SIMD3(0, 1, 0)) < 1e-6)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.5, balance: -1, blending: 0), SIMD3(0, 8.0 / 9, 1.0 / 9)) < 1e-5)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.25, balance: 0, blending: 0), SIMD3(0.25, 0.75, 0)) < 1e-6)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.25, balance: 0, blending: 1), SIMD3(0.5, 0.5, 0)) < 1e-6)
        #expect(maxDiff(ColourMath.regionWeights(luma: 0.25, balance: 0, blending: -1), SIMD3(0.0625, 0.9375, 0)) < 1e-6)
        #expect(abs(grade(grey, h: ColourTint(hue: 0, saturation: 1), balance: -1).x - 0.52187) < 1e-4) }
    @Test func hueNeverReaches360AndNearRedStillMixes() {
        let nearRed = SIMD3<Float>(1, 0, 1e-9)
        #expect(ColourMath.hsv(nearRed).x < 360)
        #expect(abs(ColourMath.bandWeights(hue: ColourMath.hsv(nearRed).x).sum() - 1) < 1e-5)
        #expect(maxDiff(mix(nearRed, sat: only(.red, -1)), SIMD3(1, 1, 1)) < 1e-5) }
    @Test func negativeHuesWrapAndMinusOneRedShiftsToThreeThirty() {
        #expect(ColourMath.rgb(hue: -30, saturation: 2.0 / 3, value: 0.75) == ColourMath.rgb(hue: 330, saturation: 2.0 / 3, value: 0.75))
        let shifted = ColourMath.hsv(mix(red, hue: only(.red, -1))); #expect(abs(shifted.x - 330) < 0.01) }
    @Test func mathRunsOffTheMainActor() async {
        let result = await Self.offMainActor()
        #expect(result.x.isFinite) }
    @concurrent static func offMainActor() async -> SIMD3<Float> {
        let weights = ColourMath.bandWeights(hue: 15)
        let mixed = ColourMath.mix(SIMD3(0.75, 0.25, 0.25), hue: weights, saturation: weights, luminance: weights)
        let hsv = ColourMath.hsv(mixed), back = ColourMath.rgb(hue: hsv.x, saturation: hsv.y, value: hsv.z)
        let regions = ColourMath.regionWeights(luma: 0.5, balance: 0, blending: 0)
        return ColourMath.grade(back, shadows: .none, midtones: .none, highlights: .none, balance: regions.x, blending: ColourMath.gradingStrength) } }
