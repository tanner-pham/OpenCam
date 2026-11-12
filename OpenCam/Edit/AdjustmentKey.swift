import Foundation

/// One adjustment slider: its name, range, step and group.
nonisolated enum AdjustmentKey: String, CaseIterable, Sendable {
    case exposure, contrast, highlights, shadows, whites, blacks, temperature, tint
    case vibrance, saturation, sharpening, noiseReduction, grain, vignette
    /// The colour mixer: hue, saturation and luminance of each `ColourBand`, in that order.
    case mixRedHue, mixRedSaturation, mixRedLuminance,
         mixOrangeHue, mixOrangeSaturation, mixOrangeLuminance,
         mixYellowHue, mixYellowSaturation, mixYellowLuminance,
         mixGreenHue, mixGreenSaturation, mixGreenLuminance,
         mixAquaHue, mixAquaSaturation, mixAquaLuminance,
         mixBlueHue, mixBlueSaturation, mixBlueLuminance,
         mixPurpleHue, mixPurpleSaturation, mixPurpleLuminance,
         mixMagentaHue, mixMagentaSaturation, mixMagentaLuminance

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
        case .mixRedHue: "Red hue"
        case .mixRedSaturation: "Red saturation"
        case .mixRedLuminance: "Red luminance"
        case .mixOrangeHue: "Orange hue"
        case .mixOrangeSaturation: "Orange saturation"
        case .mixOrangeLuminance: "Orange luminance"
        case .mixYellowHue: "Yellow hue"
        case .mixYellowSaturation: "Yellow saturation"
        case .mixYellowLuminance: "Yellow luminance"
        case .mixGreenHue: "Green hue"
        case .mixGreenSaturation: "Green saturation"
        case .mixGreenLuminance: "Green luminance"
        case .mixAquaHue: "Aqua hue"
        case .mixAquaSaturation: "Aqua saturation"
        case .mixAquaLuminance: "Aqua luminance"
        case .mixBlueHue: "Blue hue"
        case .mixBlueSaturation: "Blue saturation"
        case .mixBlueLuminance: "Blue luminance"
        case .mixPurpleHue: "Purple hue"
        case .mixPurpleSaturation: "Purple saturation"
        case .mixPurpleLuminance: "Purple luminance"
        case .mixMagentaHue: "Magenta hue"
        case .mixMagentaSaturation: "Magenta saturation"
        case .mixMagentaLuminance: "Magenta luminance"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: -5...5
        case .sharpening, .noiseReduction, .grain: 0...100
        default: -100...100   // the mixer's keys among them
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
        case .exposure, .contrast, .highlights, .shadows, .whites, .blacks, .temperature, .tint, .vibrance, .saturation,
             .mixRedHue, .mixRedSaturation, .mixRedLuminance, .mixOrangeHue, .mixOrangeSaturation, .mixOrangeLuminance,
             .mixYellowHue, .mixYellowSaturation, .mixYellowLuminance, .mixGreenHue, .mixGreenSaturation, .mixGreenLuminance,
             .mixAquaHue, .mixAquaSaturation, .mixAquaLuminance, .mixBlueHue, .mixBlueSaturation, .mixBlueLuminance,
             .mixPurpleHue, .mixPurpleSaturation, .mixPurpleLuminance, .mixMagentaHue, .mixMagentaSaturation, .mixMagentaLuminance: true
        case .sharpening, .noiseReduction, .grain, .vignette: false
        }
    }

    var group: EditorGroup {
        switch self {
        case .exposure, .contrast, .highlights, .shadows, .whites, .blacks: .light
        case .temperature, .tint, .vibrance, .saturation: .colour
        case .mixRedHue, .mixRedSaturation, .mixRedLuminance, .mixOrangeHue, .mixOrangeSaturation, .mixOrangeLuminance,
             .mixYellowHue, .mixYellowSaturation, .mixYellowLuminance, .mixGreenHue, .mixGreenSaturation, .mixGreenLuminance,
             .mixAquaHue, .mixAquaSaturation, .mixAquaLuminance, .mixBlueHue, .mixBlueSaturation, .mixBlueLuminance,
             .mixPurpleHue, .mixPurpleSaturation, .mixPurpleLuminance, .mixMagentaHue, .mixMagentaSaturation, .mixMagentaLuminance: .mix
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
