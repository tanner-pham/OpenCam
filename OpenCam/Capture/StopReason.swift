import Foundation

/// Why a recording ended before it was stopped.
nonisolated enum StopReason: Sendable, Equatable {
    case storageFull
    case interrupted
    case maximumFileSize
    case maximumDuration
    /// Any other error; the code is the `NSError` code.
    case other(code: Int)
    /// The movie output never reported the end of the clip (a stop found nothing in flight, or the session restarted);
    /// the app ended it in its place.
    case noResult
    /// The writer recorder's "Stop recording" policy ended the clip at a dropped frame.
    case droppedFrames
    /// The writer, or the camera feeding it, failed after frames were written.
    case writerFailed
}
