/// One writer trial: one size and rate with one codec, recorded for a few seconds.
nonisolated struct RecorderCheckTrialResult: Codable, Sendable {
    var target: String
    var requestedWidth: Int
    var requestedHeight: Int
    var requestedFramesPerSecond: Int
    var codec: String
    var codecType: String
    /// Set when the trial could not be set up or was not run; the reason. The other fields are then mostly empty.
    var skipReason: String?
    /// Set when the trial ran but went wrong (for example no frame arrived); the reason.
    var failure: String?
    var format: RecorderCheckFormatPick?
    /// The camera's `activeColorSpace` during the trial.
    var activeColorSpace: String?
    /// The output's `availableVideoPixelFormatTypes` at the time.
    var offeredPixelFormats: [String] = []
    /// The pixel format asked of the output: the 10-bit one if offered, else "none (output default)".
    var pixelFormatRequested = ""
    /// "recommended" when the settings came from the output's `recommendedVideoSettings`, "constructed" when the codec is not
    /// in the output's list for .mov and the settings were built here (codec, width, height only).
    var writerSettingsSource = ""
    var writerSettings = ""
    /// The colour properties that were part of the writer settings; nil when none were set (the writer then tags from the frames).
    var colourPropertiesInWriterSettings: String?
    /// False only when `canApply(outputSettings:forMediaType:)` said no.
    var writerAcceptedSettings = false
    var writerSetupError: String?
    /// Which writer calls the trial used; always "legacy add + append".
    var writerPath = "legacy add + append"
    /// `expectsMediaDataInRealTime` of the writer input, read back after it was set to true.
    var writerInputExpectsRealTime: Bool?
    var counts: RecorderCheckSinkResult?
    /// File size over the file's duration (or, if that could not be read, the span of appended presentation times plus one frame).
    var dataRateMegabitsPerSecond: Double?
    var dataRateBasis: String?
    var file: RecorderCheckFileFacts?
    var thermalBefore = ""
    var thermalAfter = ""
}
