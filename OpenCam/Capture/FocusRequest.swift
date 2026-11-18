import Foundation

/// What a gesture asks of the camera.
nonisolated enum FocusRequest: Sendable, Equatable {
    /// A tap: focus and expose there once, then watch the scene.
    case point(FocusPoint)
    /// A long press: the same, and stay.
    case lock(FocusPoint)
    /// Back to the centre, continuous, with the watch off.
    case recentre
}
