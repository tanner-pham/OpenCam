import Foundation

/// The device settings a manual control belongs to; the session applies one group at a time.
nonisolated enum ManualGroup: Sendable, CaseIterable {
    case exposure, bias, whiteBalance, focus
}
