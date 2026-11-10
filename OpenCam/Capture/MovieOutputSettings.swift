import AVFoundation

/// What the movie output is asked to encode. `MovieRecorder` turns it into the output-settings dictionary,
/// after checking each key and value against what the output reports.
nonisolated struct MovieOutputSettings: Equatable, Sendable {
    let codecType: String
    /// Bits per second; nil leaves the encoder's default rate.
    let averageBitRate: Int?

    /// A bitrate is set only for codecs with a bitrate tier (HEVC and H.264), and only when the connection accepts
    /// compression properties beside the codec (AVCaptureFileOutput.h, `setOutputSettings:forConnection:`).
    static func make(for option: VideoOption, supportedKeys: [String]) -> MovieOutputSettings {
        let acceptsBitRate = supportedKeys.contains(AVVideoCodecKey) && supportedKeys.contains(AVVideoCompressionPropertiesKey)
        let bitRate = option.codec.bitrateTier != nil && acceptsBitRate
            ? Int((DataRateEstimator.megabitsPerSecond(for: option) * 1e6).rounded())
            : nil
        return MovieOutputSettings(codecType: option.codec.codecType, averageBitRate: bitRate)
    }
}
