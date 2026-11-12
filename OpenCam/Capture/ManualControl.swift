import Foundation

/// A camera setting the user can set by hand.
nonisolated enum ManualControl: String, Sendable, CaseIterable {
    /// Raw values are the `-control` launch values.
    case shutter, iso, bias = "ev", temperature = "wb", tint, focus

    /// As the readouts read today.
    var caption: String {
        switch self {
        case .shutter: "SHUTTER"
        case .iso: "ISO"
        case .bias: "EV"
        case .temperature: "WB"
        case .tint: "TINT"
        case .focus: "FOCUS"
        }
    }

    var name: String {
        switch self {
        case .shutter: "Shutter"
        case .iso: "ISO"
        case .bias: "Exposure bias"
        case .temperature: "White balance"
        case .tint: "Tint"
        case .focus: "Focus"
        }
    }

    var group: ManualGroup {
        switch self {
        case .shutter, .iso: .exposure
        case .bias: .bias
        case .temperature, .tint: .whiteBalance
        case .focus: .focus
        }
    }

    var hasAutomatic: Bool { self != .bias }

    /// The readouts' text for the same value; nil reads "--". Units: seconds, ISO, stops, kelvin, tint, lens position.
    func text(_ value: Double?) -> String {
        let single = value.map { Float($0) }
        switch self {
        case .shutter: return ReadoutFormatter.shutter(value)
        case .iso: return ReadoutFormatter.iso(single)
        case .bias: return ReadoutFormatter.bias(single)
        case .temperature: return ReadoutFormatter.kelvin(single)
        case .tint: return ReadoutFormatter.tint(single)
        case .focus: return ReadoutFormatter.focus(single)
        }
    }

    /// What VoiceOver says; nil or a value that cannot be shown reads "Not available".
    func spoken(_ value: Double?) -> String {
        let shown = text(value)
        guard shown != ReadoutFormatter.missing else { return "Not available" }
        switch self {
        case .shutter:
            if shown.hasPrefix("1/") { return "\(shown) second" }
            let number = String(shown.dropLast())
            return number == "1" ? "1 second" : "\(number) seconds"
        case .iso: return "ISO \(shown)"
        case .bias: return "\(shown) EV"
        case .temperature: return "\(shown.dropLast()) kelvin"
        case .tint: return "Tint \(shown)"
        case .focus: return "Focus \(shown)"
        }
    }
}
