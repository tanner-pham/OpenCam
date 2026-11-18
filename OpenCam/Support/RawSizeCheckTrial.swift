/// One trial: a camera, a route, a format and a size, with what the output offered and what the capture delivered.
nonisolated struct RawSizeCheckTrial: Codable, Sendable, Equatable {
    var route: RawSizeCheckRoute
    /// "wide", "ultra wide" or "dual wide".
    var camera: String
    var deviceType: String
    var format: RawSizeCheckFormatFacts
    var sessionPreset: String
    var requestedMaxPhotoDimensions: RawSizeCheckSize?
    var availability: RawSizeCheckAvailability?
    var capture: RawSizeCheckCapture?
    /// Why no capture was made; nil when one was.
    var skipReason: String?

    /// The largest RAW picture this trial delivered, if it delivered one.
    var deliveredRawSize: RawSizeCheckSize? {
        capture?.photos.filter(\.isRaw).compactMap(\.size).max { $0.pixels < $1.pixels }
    }
}
