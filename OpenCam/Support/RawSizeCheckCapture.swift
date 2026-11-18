/// One photo request and what came back.
nonisolated struct RawSizeCheckCapture: Codable, Sendable, Equatable {
    var kind: RawSizeCheckKind
    var rawPixelFormat: String?
    var requestedMaxPhotoDimensions: RawSizeCheckSize
    /// `rawPhotoDimensions` of the resolved settings; nil when it is 0 x 0.
    var resolvedRawPhotoDimensions: RawSizeCheckSize?
    /// `photoDimensions` of the resolved settings; nil when it is 0 x 0.
    var resolvedPhotoDimensions: RawSizeCheckSize?
    var photos: [RawSizeCheckPhoto]
    var milliseconds: Int
    var isTimedOut: Bool
    var error: String?
}
