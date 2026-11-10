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

    /// `value` on the nearest step, clamped to the range. Divides a whole number of steps by the steps per unit, so 0.1 + 0.2
    /// gives exactly the `Double` written 0.3 (multiplying by 0.1 would leave 0.30000000000000004).
    func snapped(_ value: Double) -> Double {
        let stepsPerUnit = (1 / step).rounded()
        let snapped = (value * stepsPerUnit).rounded() / stepsPerUnit
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    /// True for the keys the colour table is built from (`ColourMath` reads exactly these); the others are spatial steps.
    /// Said per key, so a key added later is placed on purpose rather than by its position in `allCases`.
    var isColour: Bool {
        switch self {
        case .exposure, .contrast, .highlights, .shadows, .whites, .blacks, .temperature, .tint, .vibrance, .saturation: true
        case .sharpening, .noiseReduction, .grain, .vignette: false
        }
    }

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
