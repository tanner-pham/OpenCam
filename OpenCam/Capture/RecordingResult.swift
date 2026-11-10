import Foundation

/// One finished recording: the clip, what was asked for, how it ended, and the sidecar written beside it (nil when none was written).
nonisolated struct RecordingResult: Sendable {
    let url: URL
    let option: VideoOption
    let outcome: RecordingOutcome
    let sidecar: ClipSidecar?
}
