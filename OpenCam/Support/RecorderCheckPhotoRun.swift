/// Ten RAW photos taken one way.
nonisolated struct RecorderCheckPhotoRun: Codable, Sendable {
    var name: String
    var shots: [RecorderCheckPhotoShot] = []
    /// From the first request to the last photo's `didFinishCaptureFor` (or its timeout).
    var totalSeconds = 0.0
    var photosCompleted = 0
    /// Photos that finished without an error, over the total time.
    var photosPerSecond: Double?
}
