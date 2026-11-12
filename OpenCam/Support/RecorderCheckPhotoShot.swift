/// One RAW photo of a cadence run. Times are milliseconds from the start of its run.
nonisolated struct RecorderCheckPhotoShot: Codable, Sendable {
    var index: Int
    var requestedAtMilliseconds: Double
    /// From the request to `didFinishProcessingPhoto` for the RAW photo; nil when that callback never came.
    var requestToProcessedMilliseconds: Double?
    /// From the request to `didFinishCaptureFor`, the last callback of the request.
    var requestToCaptureFinishedMilliseconds: Double?
    /// Time to write the DNG data to the temporary directory, inside the processing callback after the time above was taken.
    var writeMilliseconds: Double?
    var dngBytes: Int?
    var error: String?
}
