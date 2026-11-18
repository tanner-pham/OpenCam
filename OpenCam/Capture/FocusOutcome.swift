import Foundation

/// What a focus request changed on the camera.
nonisolated enum FocusOutcome: Sendable, Equatable {
    case focusAndExposure, exposureOnly, focusOnly, nothing
}
