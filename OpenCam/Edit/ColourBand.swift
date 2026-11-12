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
}
