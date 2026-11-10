import Foundation

/// A clip the movie output was asked to record, kept until the output reports its file finished.
nonisolated struct PendingRecording: Sendable {
    let url: URL
    let option: VideoOption
    let recordedAt: Date
    /// Runs once the file is finished, for the clip still current only.
    let onFinish: @Sendable () -> Void
}
