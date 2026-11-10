import Foundation

/// What a recorded clip actually contains, read back from the file.
nonisolated struct ClipFacts: Codable, Sendable, Equatable {
    let codecFourCC: String
    let width: Int
    let height: Int
    let nominalFrameRate: Double
    let durationSeconds: Double
    /// Nil when the track cannot be stepped sample by sample; the sidecar then omits it.
    let frameCount: Int?
    /// Frames the requested rate implies for the duration, minus the frames in the file; never negative.
    /// Nil when the frame count is unknown.
    let droppedFrames: Int?
    /// Nil when the format extensions match no colour mode the app offers.
    let colour: ColourMode?
    /// The video track's estimated data rate.
    let megabitsPerSecond: Double
    let hasAudio: Bool
}
