/// Formats route C left out because of its cap, for one camera.
nonisolated struct RawSizeCheckSkippedFormats: Codable, Sendable, Equatable {
    var camera: String
    var count: Int
    var formats: [RawSizeCheckFormatFacts]
}
