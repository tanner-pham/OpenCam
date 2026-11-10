import Foundation

/// One saved look for the Simulator, so the Looks group and Apply look can be shown without naming one by hand.
nonisolated enum LookSeeder {
    static let warmFadeName = "Warm fade"

    static let warmFade: Adjustments = {
        var adjustments = Adjustments()
        adjustments.exposure = 0.3
        adjustments.contrast = -15
        adjustments.highlights = -20
        adjustments.shadows = 25
        adjustments.blacks = 15
        adjustments.temperature = 20
        adjustments.tint = 5
        adjustments.vibrance = 10
        adjustments.saturation = -10
        adjustments.grain = 20
        adjustments.vignette = -15
        return adjustments
    }()

    /// Nil when a look named "Warm fade" exists.
    static func seedWarmFade(into store: LookStore) throws(LookStoreError) -> Look? {
        guard !store.all().contains(where: { $0.name == warmFadeName }) else { return nil }
        return try store.save(name: warmFadeName, adjustments: warmFade)
    }
}
