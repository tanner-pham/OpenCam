import Foundation

/// One of the three tonal regions colour grading tints, in the order of `ColourMath.regionWeights`' lanes.
nonisolated enum GradingRegion: String, CaseIterable, Sendable {
    case shadows, midtones, highlights

    var title: String {
        switch self {
        case .shadows: "Shadows"
        case .midtones: "Midtones"
        case .highlights: "Highlights"
        }
    }

    /// Position in `allCases`, 0...2, and in every `SIMD3` of `GradingLanes` and `ColourMath.regionWeights`.
    var index: Int {
        switch self {
        case .shadows: 0
        case .midtones: 1
        case .highlights: 2
        }
    }

    /// The region's wheel sets its hue and saturation; its luminance has a slider of its own.
    var hueKey: AdjustmentKey {
        switch self {
        case .shadows: .gradingShadowsHue
        case .midtones: .gradingMidtonesHue
        case .highlights: .gradingHighlightsHue
        }
    }

    var saturationKey: AdjustmentKey {
        switch self {
        case .shadows: .gradingShadowsSaturation
        case .midtones: .gradingMidtonesSaturation
        case .highlights: .gradingHighlightsSaturation
        }
    }

    var luminanceKey: AdjustmentKey {
        switch self {
        case .shadows: .gradingShadowsLuminance
        case .midtones: .gradingMidtonesLuminance
        case .highlights: .gradingHighlightsLuminance
        }
    }
}
