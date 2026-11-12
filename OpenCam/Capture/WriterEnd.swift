import Foundation

/// How a writer clip came to an end.
nonisolated enum WriterEnd: Sendable, Equatable {
    case user, droppedFrames, storageFull, interrupted, cameraStopped, writerFailed, timedOut
}
