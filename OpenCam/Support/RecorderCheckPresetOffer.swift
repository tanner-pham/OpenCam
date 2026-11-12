/// What the video data output offers while the session is on the photo preset (report section A): is any Bayer format offered?
nonisolated struct RecorderCheckPresetOffer: Codable, Sendable {
    var skipReason: String?
    var wasSessionRunning = false
    /// How long the check waited after `startRunning()` returned before reading the lists: until the session reported running, and at least 0.8 s.
    var waitedMilliseconds = 0.0
    /// The format the preset picked, as "WxH subtype".
    var activeFormat = ""
    var pixelFormats: [String] = []
    /// The pixel formats `AVCapturePhotoOutput.isBayerRAWPixelFormat` says are Bayer.
    var bayerPixelFormats: [String] = []
    var videoCodecTypes: [String] = []
}
