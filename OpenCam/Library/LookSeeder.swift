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

/// The look the curve, mixer and grading screenshots open with (`-seedStudy on -editorLook "Colour study"`).
nonisolated extension LookSeeder {
    static let colourStudyName = "Colour study"

    /// An S curve with lifted blacks and dimmed whites, and blue lifted in the blacks.
    static let colourStudy: Adjustments = {
        var adjustments = Adjustments()
        adjustments.curves.master = ToneCurve(points: [CurvePoint(x: 0, y: 0.06), CurvePoint(x: 0.25, y: 0.2),
                                                       CurvePoint(x: 0.75, y: 0.82), CurvePoint(x: 1, y: 0.97)])
        adjustments.curves.blue = ToneCurve(points: [CurvePoint(x: 0, y: 0.04), CurvePoint(x: 1, y: 1)])
        return adjustments
    }()

    /// Nil when a look named "Colour study" exists.
    static func seedColourStudy(into store: LookStore) throws(LookStoreError) -> Look? {
        guard !store.all().contains(where: { $0.name == colourStudyName }) else { return nil }
        return try store.save(name: colourStudyName, adjustments: colourStudy)
    }
}
