import CoreGraphics

/// The square drawn where the viewfinder was touched. `serial` tells one marker from the next, so an old fade does not clear a new one.
nonisolated struct FocusMarker: Sendable, Equatable {
    let viewPoint: CGPoint
    let serial: Int
    let isLocked: Bool
}
