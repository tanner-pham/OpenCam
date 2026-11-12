/// The counts of one writer trial, handed back by the sink once it is finished. Presentation times are in seconds on the
/// camera's clock; the effective rates divide the frames after the first by the time between the first and the last.
nonisolated struct RecorderCheckSinkResult: Codable, Sendable {
    /// Frames the camera handed to the delegate.
    var framesDelivered = 0
    /// Frames the writer input accepted.
    var framesAppended = 0
    /// Frames dropped by this check because the input said it was not ready (`appendImmediately` returned false).
    var framesNotAppendedInputNotReady = 0
    /// Frames not offered to the writer because an earlier append had failed.
    var framesNotAppendedAfterWriterFailure = 0
    /// Frames the output reported dropped through the drop callback.
    var framesDroppedByOutput = 0
    /// Dropped frames counted by the reason the output gave.
    var dropReasons: [String: Int] = [:]
    var firstDeliveredPTS: Double?
    var lastDeliveredPTS: Double?
    var effectiveDeliveredFPS: Double?
    var firstAppendedPTS: Double?
    var lastAppendedPTS: Double?
    var effectiveAppendedFPS: Double?
    /// Wall-clock time spent inside `appendImmediately`, summed, per call on average, and at the worst single call.
    var appendTotalMilliseconds = 0.0
    var appendMeanMilliseconds: Double?
    var appendWorstMilliseconds = 0.0
    var appendError: String?
    var writerStatus = ""
    var writerError: String?
    var firstFrame: RecorderCheckFrameFacts?
}
