import Foundation

/// The tabs of the editor's panel.
nonisolated enum EditorGroup: String, CaseIterable, Sendable {
    case light, colour, curve, mix, grading, detail, effects, looks

    var title: String {
        switch self {
        case .light: "Light"
        case .colour: "Colour"
        case .curve: "Curve"
        case .mix: "Mix"
        case .grading: "Grading"
        case .detail: "Detail"
        case .effects: "Effects"
        case .looks: "Looks"
        }
    }

    var keys: [AdjustmentKey] {
        switch self {
        case .light: [.exposure, .contrast, .highlights, .shadows, .whites, .blacks]
        case .colour: [.temperature, .tint, .vibrance, .saturation]
        case .mix: ColourBand.allCases.flatMap(\.keys)
        case .grading: GradingRegion.allCases.flatMap { [$0.hueKey, $0.saturationKey, $0.luminanceKey] } + [.gradingBlending, .gradingBalance]
        case .detail: [.sharpening, .noiseReduction]
        case .effects: [.grain, .vignette]
        case .curve, .looks: []
        }
    }
}
