import Foundation

/// What a recorded clip actually contains, read back from the file.
nonisolated struct ClipFacts: Codable, Sendable, Equatable {
    let codecFourCC: String
    let width: Int
    let height: Int
    let nominalFrameRate: Double
    let durationSeconds: Double
    let frameCount: Int
    /// Frames the requested rate implies for the duration, minus the frames in the file; never negative.
    let droppedFrames: Int
    /// Nil when the format extensions match no colour mode the app offers.
    let colour: ColourMode?
    /// The video track's estimated data rate.
    let megabitsPerSecond: Double
    let hasAudio: Bool
}
