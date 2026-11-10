import Foundation

/// One adjustment slider: its name, range, step and group.
nonisolated enum AdjustmentKey: String, CaseIterable, Sendable {
    case exposure, contrast, highlights, shadows, whites, blacks, temperature, tint
    case vibrance, saturation, sharpening, noiseReduction, grain, vignette

    var title: String {
        switch self {
        case .exposure: "Exposure"
        case .contrast: "Contrast"
        case .highlights: "Highlights"
        case .shadows: "Shadows"
        case .whites: "Whites"
        case .blacks: "Blacks"
        case .temperature: "Temperature"
        case .tint: "Tint"
        case .vibrance: "Vibrance"
        case .saturation: "Saturation"
        case .sharpening: "Sharpening"
        case .noiseReduction: "Noise reduction"
        case .grain: "Grain"
        case .vignette: "Vignette"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: -5...5
        case .sharpening, .noiseReduction, .grain: 0...100
        default: -100...100
        }
    }

    var step: Double { self == .exposure ? 0.1 : 1 }

    var group: EditorGroup {
        switch self {
        case .exposure, .contrast, .highlights, .shadows, .whites, .blacks: .light
        case .temperature, .tint, .vibrance, .saturation: .colour
        case .sharpening, .noiseReduction: .detail
        case .grain, .vignette: .effects
        }
    }

    func valueText(_ value: Double) -> String {
        if self == .exposure {
            let tenths = (value * 10).rounded() / 10
            return tenths == 0 ? "0.0" : String(format: "%+.1f", tenths)
        }
        let whole = Int(value.rounded())
        if range.lowerBound == 0 { return String(whole) }
        return whole == 0 ? "0" : String(format: "%+d", whole)
    }
}
