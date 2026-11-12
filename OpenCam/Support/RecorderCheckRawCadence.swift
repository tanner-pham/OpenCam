/// Report section C: how fast RAW photos can be taken in a row on the photo preset.
nonisolated struct RecorderCheckRawCadence: Codable, Sendable {
    var skipReason: String?
    var sessionPreset = ""
    /// The format the preset picked, as "WxH subtype".
    var activeFormat = ""
    var maxPhotoDimensions = ""
    var rawPixelFormat = ""
    var photoQualityPrioritization = ""
    /// Each photo requested when the previous one had finished.
    var oneAfterAnother: RecorderCheckPhotoRun?
    /// Each photo requested 100 ms after the previous request, without waiting.
    var every100Milliseconds: RecorderCheckPhotoRun?
}
