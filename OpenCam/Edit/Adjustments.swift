import Foundation

/// The fourteen adjustment values of an edit or a look, and its point curves. Zero (and identity curves) is "no change".
nonisolated struct Adjustments: Codable, Sendable, Hashable {
    var exposure = 0.0, contrast = 0.0, highlights = 0.0, shadows = 0.0, whites = 0.0, blacks = 0.0, temperature = 0.0, tint = 0.0
    var vibrance = 0.0, saturation = 0.0, sharpening = 0.0, noiseReduction = 0.0, grain = 0.0, vignette = 0.0
    var curves = ToneCurves()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks, temperature, tint
        case vibrance, saturation, sharpening, noiseReduction, grain, vignette
        case curves
    }

    /// Every key is optional, unknown keys are ignored, and each value is clamped to its range.
    /// A `curves` value that is present but malformed throws, so the edit stays unreadable rather than being overwritten.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in AdjustmentKey.allCases {
            guard let codingKey = CodingKeys(rawValue: key.rawValue) else { continue }
            self[key] = try container.decodeIfPresent(Double.self, forKey: codingKey) ?? 0
        }
        curves = try container.decodeIfPresent(ToneCurves.self, forKey: .curves) ?? ToneCurves()
    }

    /// Writes every scalar key, plus `curves` only when it is not identity, so an edit without curves encodes as it always did.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for key in AdjustmentKey.allCases {
            guard let codingKey = CodingKeys(rawValue: key.rawValue) else { continue }
            try container.encode(self[key], forKey: codingKey)
        }
        if !curves.isIdentity { try container.encode(curves, forKey: .curves) }
    }

    subscript(key: AdjustmentKey) -> Double {
        get {
            switch key {
            case .exposure: exposure
            case .contrast: contrast
            case .highlights: highlights
            case .shadows: shadows
            case .whites: whites
            case .blacks: blacks
            case .temperature: temperature
            case .tint: tint
            case .vibrance: vibrance
            case .saturation: saturation
            case .sharpening: sharpening
            case .noiseReduction: noiseReduction
            case .grain: grain
            case .vignette: vignette
            }
        }
        set {
            let value = min(max(newValue, key.range.lowerBound), key.range.upperBound)
            switch key {
            case .exposure: exposure = value
            case .contrast: contrast = value
            case .highlights: highlights = value
            case .shadows: shadows = value
            case .whites: whites = value
            case .blacks: blacks = value
            case .temperature: temperature = value
            case .tint: tint = value
            case .vibrance: vibrance = value
            case .saturation: saturation = value
            case .sharpening: sharpening = value
            case .noiseReduction: noiseReduction = value
            case .grain: grain = value
            case .vignette: vignette = value
            }
        }
    }

    func setting(_ key: AdjustmentKey, to value: Double) -> Adjustments {
        var copy = self
        copy[key] = value
        return copy
    }

    var isIdentity: Bool { AdjustmentKey.allCases.allSatisfy { self[$0] == 0 } && curves.isIdentity }

    /// Equal at every key once each value is on its step, so values that read the same compare the same.
    /// Curves compare exactly: `ToneCurve` already stores snapped values.
    func matches(_ other: Adjustments) -> Bool {
        AdjustmentKey.allCases.allSatisfy { $0.snapped(self[$0]) == $0.snapped(other[$0]) } && curves == other.curves
    }

    /// True when any colour key (`AdjustmentKey.isColour`) is not zero or any curve is not identity.
    var hasColourChanges: Bool {
        AdjustmentKey.allCases.contains { $0.isColour && self[$0] != 0 } || !curves.isIdentity
    }

    /// Only what the colour table depends on: the colour keys and the curves. The spatial keys are zeroed.
    var colourPart: Adjustments {
        var colour = Adjustments()
        for key in AdjustmentKey.allCases where key.isColour { colour[key] = self[key] }
        colour.curves = curves
        return colour
    }
}
