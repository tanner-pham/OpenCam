import Foundation

/// A point in the camera's own picture, as `focusPointOfInterest` and `exposurePointOfInterest` take it: both numbers in
/// 0...1, (0, 0) the top left of the sensor's unturned image and (1, 1) its bottom right.
nonisolated struct FocusPoint: Sendable, Equatable {
    let x: Double
    let y: Double

    static let centre = FocusPoint(x: 0.5, y: 0.5)
}
