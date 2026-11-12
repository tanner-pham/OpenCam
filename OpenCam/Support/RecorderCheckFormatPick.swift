/// The camera format chosen for one size and rate, as the report records it.
nonisolated struct RecorderCheckFormatPick: Codable, Sendable {
    var cameraName: String
    var cameraID: String
    var width: Int
    var height: Int
    /// Every frame-rate range the format offers, as "minimum-maximum".
    var frameRateRanges: [String]
    /// The format's media subtype as a four-character code.
    var mediaSubType: String
    /// 10 for the 10-bit subtypes this check knows, else 8. Read from the subtype, not measured.
    var bitDepthFromSubType: Int
    var supportedColorSpaces: [String]
    var isVideoBinned: Bool
    var isVideoHDRSupported: Bool
    /// How many formats the camera offers at this size and rate; the pick is the best of them.
    var candidateCount: Int
}
