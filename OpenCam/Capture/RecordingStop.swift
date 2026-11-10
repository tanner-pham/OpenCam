import Foundation

/// What a stop request does, decided by `RecordingTracker.requestStop()`.
nonisolated enum RecordingStop: Sendable, Equatable {
    /// The output is recording the pending clip: stop it now.
    case stopNow
    /// The pending clip has not started writing yet; it stops as soon as it does.
    case deferred
    /// No clip is recording, but a finished one's result is still to come.
    case awaitingResult
    /// Nothing is in flight; no result will follow.
    case nothingInFlight

    /// True when a recording result will follow.
    var isClipInFlight: Bool { self != .nothingInFlight }
}
