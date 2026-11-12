import Foundation

/// One control point of a tone curve: input `x` and output `y`, both 0...1.
nonisolated struct CurvePoint: Codable, Sendable, Hashable {
    var x: Double
    var y: Double
}
