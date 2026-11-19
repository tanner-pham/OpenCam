/// What became of a trial.
nonisolated enum RawSizeCheckOutcome: String, Codable, Sendable {
    /// A photo request was made (it may still have failed or timed out; the capture says).
    case ran
    /// The phone did not offer what the trial needs.
    case refused
    /// The check would not risk the request: a precondition that keeps AVFoundation from raising an exception did not hold.
    case unsafe
    /// The time budget ran out before the trial started.
    case budget
}
