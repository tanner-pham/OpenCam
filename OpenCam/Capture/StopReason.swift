import Foundation

/// Why a recording ended before it was stopped.
nonisolated enum StopReason: Sendable, Equatable {
    case storageFull
    case interrupted
    case maximumFileSize
    case maximumDuration
    /// Any other error; the code is the `NSError` code.
    case other(code: Int)
}
