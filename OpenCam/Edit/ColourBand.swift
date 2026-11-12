import Foundation

/// One of the eight hue bands of the colour mixer, in the order the mixer's vectors use.
nonisolated enum ColourBand: String, CaseIterable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    var title: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .aqua: "Aqua"
        case .blue: "Blue"
        case .purple: "Purple"
        case .magenta: "Magenta"
        }
    }

    /// The hue this band peaks at, in degrees.
    var centre: Float {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .aqua: 180
        case .blue: 240
        case .purple: 270
        case .magenta: 300
        }
    }

    /// Position in `allCases`, 0...7, and in every `SIMD8` the mixer takes.
    var index: Int {
        switch self {
        case .red: 0
        case .orange: 1
        case .yellow: 2
        case .green: 3
        case .aqua: 4
        case .blue: 5
        case .purple: 6
        case .magenta: 7
        }
    }

    /// The three keys of this band's sliders, in the order they are shown.
    var hueKey: AdjustmentKey {
        switch self {
        case .red: .mixRedHue
        case .orange: .mixOrangeHue
        case .yellow: .mixYellowHue
        case .green: .mixGreenHue
        case .aqua: .mixAquaHue
        case .blue: .mixBlueHue
        case .purple: .mixPurpleHue
        case .magenta: .mixMagentaHue
        }
    }

    var saturationKey: AdjustmentKey {
        switch self {
        case .red: .mixRedSaturation
        case .orange: .mixOrangeSaturation
        case .yellow: .mixYellowSaturation
        case .green: .mixGreenSaturation
        case .aqua: .mixAquaSaturation
        case .blue: .mixBlueSaturation
        case .purple: .mixPurpleSaturation
        case .magenta: .mixMagentaSaturation
        }
    }

    var luminanceKey: AdjustmentKey {
        switch self {
        case .red: .mixRedLuminance
        case .orange: .mixOrangeLuminance
        case .yellow: .mixYellowLuminance
        case .green: .mixGreenLuminance
        case .aqua: .mixAquaLuminance
        case .blue: .mixBlueLuminance
        case .purple: .mixPurpleLuminance
        case .magenta: .mixMagentaLuminance
        }
    }

    var keys: [AdjustmentKey] { [hueKey, saturationKey, luminanceKey] }

    /// The colour of this band's button: the band's hue at a fixed saturation and value, Display P3-encoded.
    var swatch: SIMD3<Float> { ColourMath.rgb(hue: centre, saturation: 0.8, value: 0.9) }
}
