import Foundation

/// What a capture came to after its look: the camera's result, unchanged, and the notice the look adds, if any.
nonisolated struct LookCaptureOutcome: Sendable, Equatable {
    let result: PhotoCaptureResult
    let notice: String?
}
