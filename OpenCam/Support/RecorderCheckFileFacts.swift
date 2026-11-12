/// What the finished movie says about itself, read back with `AVURLAsset`.
nonisolated struct RecorderCheckFileFacts: Codable, Sendable {
    var fileBytes: Int64?
    var durationSeconds: Double?
    /// The video track's codec as a four-character code.
    var codec: String?
    var naturalWidth: Double?
    var naturalHeight: Double?
    var nominalFrameRate: Double?
    var colourPrimaries: String?
    var transferFunction: String?
    var yCbCrMatrix: String?
    var bitsPerComponent: Int?
    var readError: String?
}
