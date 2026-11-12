import Foundation

/// ITU-R BT.2100 HLG. a = 0.17883277, b = 1 - 4a, c = 0.5 - a ln(4a).
nonisolated enum HLGCurve {
    private static let a = 0.17883277
    private static let b = 1 - 4 * a
    private static let c = 0.5 - a * log(4 * a)

    /// The scene light (0...1 for signals 0...1) an HLG signal stands for. A negative signal reads as 0.
    static func sceneLight(signal: Double) -> Double {
        let s = max(signal, 0)
        return s <= 0.5 ? s * s / 3 : (exp((s - c) / a) + b) / 12
    }

    /// The HLG signal for a scene light. Continued above a light of 1, and 0 for a light of 0 or less.
    static func signal(sceneLight: Double) -> Double {
        let e = max(sceneLight, 0)
        return e <= 1.0 / 12 ? (3 * e).squareRoot() : a * log(12 * e - b) + c
    }
}
