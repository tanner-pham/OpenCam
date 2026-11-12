import Foundation

/// The adjustment values of an edit or a look (fourteen stored properties and the mixer's), and its point curves. Zero (and identity curves) is "no change".
nonisolated struct Adjustments: Codable, Sendable, Hashable {
    var exposure = 0.0, contrast = 0.0, highlights = 0.0, shadows = 0.0, whites = 0.0, blacks = 0.0, temperature = 0.0, tint = 0.0
    var vibrance = 0.0, saturation = 0.0, sharpening = 0.0, noiseReduction = 0.0, grain = 0.0, vignette = 0.0
    var curves = ToneCurves()

    /// Every key added after the fourteen above (the mixer's). Never holds a zero: the subscript removes a key set to 0, so
    /// the synthesized `Equatable` and `Hashable` stay right and a value moved back to 0 equals `Adjustments()`.
    private var toolValues: [AdjustmentKey: Double] = [:]
    /// The mixer's values as vectors for the colour table, updated only where `toolValues` is (the subscript's added-key branch).
    private(set) var mixer = MixerLanes()

    init() {}

    /// A key named by its raw value, or "curves".
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        init(_ key: AdjustmentKey) { stringValue = key.rawValue }
        static let curves = Key(stringValue: "curves")
    }

    /// Every key is optional, unknown keys are ignored, and each value is clamped to its range.
    /// A `curves` value that is present but malformed throws, so the edit stays unreadable rather than being overwritten.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in AdjustmentKey.allCases {
            self[key] = try container.decodeIfPresent(Double.self, forKey: Key(key)) ?? 0
        }
        curves = try container.decodeIfPresent(ToneCurves.self, forKey: .curves) ?? ToneCurves()
    }

    /// Writes the fourteen original keys always, each later key only when it is not 0, and `curves` only when it is not
    /// identity, so an edit that uses none of the later tools encodes as it always did.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for key in AdjustmentKey.allCases.prefix(Self.originalKeyCount) {
            try container.encode(self[key], forKey: Key(key))
        }
        // In `allCases` order, so the same edit always writes the same bytes.
        for key in AdjustmentKey.allCases.dropFirst(Self.originalKeyCount) {
            if let value = toolValues[key] { try container.encode(value, forKey: Key(key)) }
        }
        if !curves.isIdentity { try container.encode(curves, forKey: .curves) }
    }

    /// True when any mixer value is not 0. One stored flag, so the colour table can ask it at every lattice point.
    var hasMixerValues: Bool { !mixer.isZero }

    /// The keys that have a stored property of their own.
    private static let originalKeyCount = 14

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
            default: toolValues[key] ?? 0
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
            default:
                toolValues[key] = value == 0 ? nil : value
                mixer.set(key, to: value)
            }
        }
    }

    func setting(_ key: AdjustmentKey, to value: Double) -> Adjustments {
        var copy = self
        copy[key] = value
        return copy
    }

    var isIdentity: Bool { toolValues.isEmpty && curves.isIdentity && AdjustmentKey.allCases.prefix(Self.originalKeyCount).allSatisfy { self[$0] == 0 } }

    /// Equal at every key once each value is on its step, so values that read the same compare the same.
    /// Curves compare exactly: `ToneCurve` already stores snapped values.
    func matches(_ other: Adjustments) -> Bool {
        AdjustmentKey.allCases.allSatisfy { $0.snapped(self[$0]) == $0.snapped(other[$0]) } && curves == other.curves
    }

    /// True when any colour key (`AdjustmentKey.isColour`) is not zero or any curve is not identity.
    var hasColourChanges: Bool {
        toolValues.keys.contains(where: \.isColour) || !curves.isIdentity || AdjustmentKey.allCases.prefix(Self.originalKeyCount).contains { $0.isColour && self[$0] != 0 }
    }

    /// Only what the colour table depends on: the colour keys and the curves. The spatial keys are zeroed.
    var colourPart: Adjustments {
        var colour = Adjustments()
        for key in AdjustmentKey.allCases where key.isColour { colour[key] = self[key] }
        colour.curves = curves
        return colour
    }
}
