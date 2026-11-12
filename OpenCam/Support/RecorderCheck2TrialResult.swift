/// One trial of the second check: a size, rate and codec recorded for 30 seconds with a preview, sound and (optionally) a colour table pass.
nonisolated struct RecorderCheck2TrialResult: Codable, Sendable {
    var label: String
    var requestedWidth: Int
    var requestedHeight: Int
    var requestedFramesPerSecond: Int
    var codec: String
    var codecType: String
    var usesColourTable: Bool
    var skipReason: String?
    var failure: String?
    var format: RecorderCheckFormatPick?
    var activeColorSpace: String?
    var offeredPixelFormats: [String] = []
    var pixelFormatRequested = ""
    var writerSettingsSource = ""
    var writerSettings = ""
    var writerAcceptedSettings = false
    var writerSetupError: String?
    /// Always "legacy add + append" (with a pixel buffer adaptor for the colour table trials).
    var writerPath = "legacy add + append"
    var writerInputExpectsRealTime: Bool?
    var video: RecorderCheckSinkResult?
    var audio = RecorderCheck2AudioFacts()
    /// The colour table pass; nil when the trial has none.
    var render: RecorderCheck2RenderStats?
    /// Whether the preview layer reported `isPreviewing` about 3 seconds in and again at the end.
    var wasPreviewingEarly: Bool?
    var wasPreviewingAtEnd: Bool?
    /// Mean luma of a sparse sample of the Y plane, 0 to 1, black and white taken from the format's range. Below about 0.1 the
    /// camera was looking at darkness.
    var meanLumaFirstFrame: Double?
    var meanLumaLastFrame: Double?
    var dataRateMegabitsPerSecond: Double?
    var dataRateBasis: String?
    var file: RecorderCheckFileFacts?
    var thermalBefore = ""
    var thermalAfter = ""
    var batteryPercentBefore: Int?
    var batteryPercentAfter: Int?
    var isLowPowerModeEnabled = false
    var freeDiskBytesBefore: Int64 = 0
    /// Read while the movie still existed.
    var freeDiskBytesAfter: Int64 = 0
    var freeDiskBytesAfterDelete: Int64 = 0
}
