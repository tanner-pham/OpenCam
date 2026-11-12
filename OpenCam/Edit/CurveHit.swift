import Foundation

/// What a touch on a tone curve lands on: a point (its index), the line between the end points, or nothing.
nonisolated enum CurveHit: Equatable, Sendable {
    case point(Int), curve, none
}
