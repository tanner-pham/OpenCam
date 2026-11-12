/// What the video data output offers while the session is on the photo preset (report section A): is any Bayer format offered?
nonisolated struct RecorderCheckPresetOffer: Codable, Sendable {
    var skipReason: String?
    var wasSessionRunning = false
    /// The format the preset picked, as "WxH subtype".
    var activeFormat = ""
    var pixelFormats: [String] = []
    /// The pixel formats `AVCapturePhotoOutput.isBayerRAWPixelFormat` says are Bayer.
    var bayerPixelFormats: [String] = []
    var videoCodecTypes: [String] = []
}
