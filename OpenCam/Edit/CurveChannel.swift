import Foundation

/// Which curve of a `ToneCurves` is meant: the RGB (master) curve or one colour channel's own.
nonisolated enum CurveChannel: String, CaseIterable, Sendable {
    case master, red, green, blue

    var title: String {
        switch self {
        case .master: "RGB"
        case .red: "Red"
        case .green: "Green"
        case .blue: "Blue"
        }
    }
}
