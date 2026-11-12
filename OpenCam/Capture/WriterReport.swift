import Foundation

/// What a writer clip came to, read once after it ends.
nonisolated struct WriterReport: Sendable {
    let end: WriterEnd
    let facts: DropFacts
    /// True when at least one video frame was written.
    let hasFrames: Bool
    /// The writer's own failure, for the sidecar and the log; never shown on screen.
    let errorText: String?
}
