import Foundation

/// Colour grading's values as `ColourMath.grade(_:lanes:)` reads them, with everything that is the same for every colour of a
/// table worked out once: each region's push and lift at full weight, and the pivot and exponent of the region weights.
/// A pure function of `Adjustments`' grading values, kept beside them and rebuilt from them whole on every write (the
/// subscript's added-key branch), so the colour table reads a few vectors at each lattice point instead of eleven dictionary
/// entries, three hue conversions and a power of two.
nonisolated struct GradingLanes: Sendable, Hashable {
    /// What each region adds to a colour at full weight: `gradingStrength * saturation * o`, where `c = rgb(hue, 1, 1)` and
    /// `o = c - luma(c)` (a tint that keeps luma).
    private(set) var shadowsPush = SIMD3<Float>.zero
    private(set) var midtonesPush = SIMD3<Float>.zero
    private(set) var highlightsPush = SIMD3<Float>.zero
    /// Each region's lift at full weight, `gradingLuminanceReach * luminance`, as (shadows, midtones, highlights).
    private(set) var lift = SIMD3<Float>.zero
    /// The luma that splits shadows from highlights, from Balance.
    private(set) var pivot: Float = 0.5
    /// The power of the region weights, from Blending.
    private(set) var exponent: Float = 2
    /// True when every saturation and luminance is 0: grading then changes nothing, whatever the hues, Blending and Balance.
    private(set) var isZero = true

    /// The values themselves, each as (shadows, midtones, highlights): hue in degrees, saturation 0...1, luminance -1...1.
    private var hue = SIMD3<Float>.zero
    private var saturation = SIMD3<Float>.zero
    private var luminance = SIMD3<Float>.zero
    /// -1...1 each.
    private var balance: Float = 0
    private var blending: Float = 0

    init() { derive() }

    init(shadows: ColourTint, midtones: ColourTint, highlights: ColourTint, balance: Float, blending: Float) {
        hue = SIMD3(shadows.hue, midtones.hue, highlights.hue)
        saturation = SIMD3(shadows.saturation, midtones.saturation, highlights.saturation)
        luminance = SIMD3(shadows.luminance, midtones.luminance, highlights.luminance)
        self.balance = balance
        self.blending = blending
        derive()
    }

    /// Writes `value` for a grading key, in the key's own units (a hue in degrees, the others -100...100 or 0...100); any other
    /// key is ignored.
    mutating func set(_ key: AdjustmentKey, to value: Double) {
        guard key.group == .grading else { return }
        let unit = Float(value) / 100
        switch key {
        case .gradingBalance: balance = unit
        case .gradingBlending: blending = unit
        default:
            for region in GradingRegion.allCases {
                switch key {
                case region.hueKey: hue[region.index] = Float(value)
                case region.saturationKey: saturation[region.index] = unit
                case region.luminanceKey: luminance[region.index] = unit
                default: continue
                }
            }
        }
        derive()
    }

    /// Rebuilds every derived lane from the values alone, so equal values always give equal lanes.
    private mutating func derive() {
        shadowsPush = ColourMath.gradingPush(hue: hue.x, saturation: saturation.x)
        midtonesPush = ColourMath.gradingPush(hue: hue.y, saturation: saturation.y)
        highlightsPush = ColourMath.gradingPush(hue: hue.z, saturation: saturation.z)
        lift = ColourMath.gradingLuminanceReach * luminance
        pivot = ColourMath.gradingPivot(balance: balance)
        exponent = ColourMath.gradingExponent(blending: blending)
        isZero = saturation == .zero && luminance == .zero
    }
}
