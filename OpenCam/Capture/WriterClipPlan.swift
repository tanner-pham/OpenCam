import Foundation

/// Everything the writer needs to open one clip, decided from the selected option before anything touches AVFoundation.
nonisolated struct WriterClipPlan: Sendable, Equatable {
    let url: URL
    let codecType: String
    let width: Int
    let height: Int
    /// Bits per second for the HEVC tiers; nil for ProRes, whose rate the codec fixes.
    let averageBitRate: Int?
    let frameRate: Int
    /// Degrees clockwise the picture must turn to be upright; written to the track as its transform, so no buffer is rotated.
    let rotationDegrees: Double
    /// True for the baked Log profile.
    let bakesLog: Bool
    let policy: DropPolicy
    let minFreeBytes: Int64

    /// `bufferWidth` and `bufferHeight` are the camera frames' size (the active format's), which is the size of the file.
    static func make(option: VideoOption, url: URL, bufferWidth: Int, bufferHeight: Int, rotationDegrees: Double,
                     policy: DropPolicy, minFreeBytes: Int64) -> WriterClipPlan {
        let bitRate = option.codec.bitrateTier != nil ? Int((DataRateEstimator.megabitsPerSecond(for: option) * 1e6).rounded()) : nil
        return WriterClipPlan(url: url, codecType: option.codec.codecType, width: bufferWidth, height: bufferHeight,
                              averageBitRate: bitRate, frameRate: option.frameRate, rotationDegrees: rotationDegrees,
                              bakesLog: option.colour == .log, policy: policy, minFreeBytes: minFreeBytes)
    }
}
