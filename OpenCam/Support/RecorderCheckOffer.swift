/// What the video data output offers on the camera format picked for one size and rate (report section A).
nonisolated struct RecorderCheckOffer: Codable, Sendable {
    var target: String
    /// Set when the offer could not be read; the reason.
    var skipReason: String?
    var format: RecorderCheckFormatPick?
    var activeColorSpace: String?
    var wasSessionRunning = false
    /// How long the check waited after `startRunning()` returned before reading the lists: until the session reported running, and at least 0.8 s.
    var waitedMilliseconds = 0.0
    /// `availableVideoCVPixelFormatTypes` (the header's name; Swift: `availableVideoPixelFormatTypes`), four-character codes.
    var pixelFormats: [String] = []
    /// `availableVideoCodecTypes`: what the output's own `videoSettings` can use.
    var videoCodecTypes: [String] = []
    /// `availableVideoCodecTypesForAssetWriter(writingTo: .mov)`: what `recommendedVideoSettings` accepts.
    var assetWriterCodecTypesForMov: [String] = []
    /// The output's `videoSettings` as it stands (sorted text).
    var currentVideoSettings = ""
    /// `recommendedVideoSettings(forVideoCodecType:assetWriterOutputFileType: .mov)` per codec, as sorted text. A codec the
    /// writer list does not include is not asked (the header says that raises an exception) and says so instead.
    var recommendedSettings: [String: String] = [:]
}
