/// What happened to the sound in one trial.
nonisolated struct RecorderCheck2AudioFacts: Codable, Sendable {
    /// "recorded", "not authorized" (microphone access was not already granted; it is never asked for), or why it could not be set up.
    var status = "not tried"
    /// "recommended" (`recommendedAudioSettingsForAssetWriter`) or "hand-built AAC".
    var settingsSource = ""
    var settings = ""
    var inputExpectsRealTime: Bool?
    var buffersDelivered = 0
    var buffersAppended = 0
    /// Delivered while the audio input said it was not ready, and dropped.
    var buffersNotAppendedInputNotReady = 0
    /// Delivered before the first video frame started the writing session, and dropped.
    var buffersNotAppendedBeforeVideoStart = 0
    /// Delivered with no audio input on the writer, or after an audio append had failed.
    var buffersNotAppendedOther = 0
    var appendError: String?
}
