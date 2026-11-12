import Foundation

/// What just happened, for the views that give feedback. Each value changes exactly once per event.
/// A sweep's clips are not the user's recordings and change nothing.
nonisolated struct CaptureFeedback: Sendable, Equatable {
    var photosTaken = 0        // a photo request was made (not: the press was refused)
    var recordingsStarted = 0  // a recording actually began
    var recordingsStopped = 0  // a recording ended, for any reason
    var controlSteps = 0       // the open manual slider's thumb crossed a detent
}
