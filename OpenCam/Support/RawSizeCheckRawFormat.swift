/// One RAW pixel format the photo output offered.
nonisolated struct RawSizeCheckRawFormat: Codable, Sendable, Equatable {
    var code: String
    /// "bayer", "proRAW" or "other".
    var kind: String
}
