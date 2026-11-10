import Foundation

/// The fourteen adjustment values of an edit or a look. Zero is "no change" for every one.
nonisolated struct Adjustments: Codable, Sendable, Hashable {
    var exposure = 0.0, contrast = 0.0, highlights = 0.0, shadows = 0.0, whites = 0.0, blacks = 0.0, temperature = 0.0, tint = 0.0
    var vibrance = 0.0, saturation = 0.0, sharpening = 0.0, noiseReduction = 0.0, grain = 0.0, vignette = 0.0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case exposure, contrast, highlights, shadows, whites, blacks, temperature, tint
        case vibrance, saturation, sharpening, noiseReduction, grain, vignette
    }

    /// Every key is optional, unknown keys are ignored, and each value is clamped to its range.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in AdjustmentKey.allCases {
            guard let codingKey = CodingKeys(rawValue: key.rawValue) else { continue }
            self[key] = try container.decodeIfPresent(Double.self, forKey: codingKey) ?? 0
        }
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

    var isIdentity: Bool { AdjustmentKey.allCases.allSatisfy { self[$0] == 0 } }

    /// Equal at every key once each value is on its step, so values that read the same compare the same.
    func matches(_ other: Adjustments) -> Bool {
        AdjustmentKey.allCases.allSatisfy { $0.snapped(self[$0]) == $0.snapped(other[$0]) }
    }

    /// True when any of exposure through saturation is not zero.
    var hasColourChanges: Bool {
        AdjustmentKey.allCases.prefix { $0 != .sharpening }.contains { self[$0] != 0 }
    }
}
