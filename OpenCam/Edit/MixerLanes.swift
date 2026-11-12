import Foundation

/// The colour mixer's values as the lanes `ColourMath.mix` takes: one `SIMD8` each for hue, saturation and luminance, in
/// `ColourBand` order, each value divided by 100. A pure function of `Adjustments`' stored mixer values, kept beside them so the
/// colour table reads three vectors at every lattice point instead of 24 dictionary entries.
nonisolated struct MixerLanes: Sendable, Hashable {
    private(set) var hue = SIMD8<Float>(repeating: 0)
    private(set) var saturation = SIMD8<Float>(repeating: 0)
    private(set) var luminance = SIMD8<Float>(repeating: 0)
    /// True when every lane is 0, so the mixer changes nothing.
    private(set) var isZero = true

    /// Writes `value` (-100...100) for a mixer key; any other key is ignored.
    mutating func set(_ key: AdjustmentKey, to value: Double) {
        let lane = Float(value) / 100
        for band in ColourBand.allCases {
            switch key {
            case band.hueKey: hue[band.index] = lane
            case band.saturationKey: saturation[band.index] = lane
            case band.luminanceKey: luminance[band.index] = lane
            default: continue
            }
        }
        isZero = hue == .zero && saturation == .zero && luminance == .zero
    }
}
