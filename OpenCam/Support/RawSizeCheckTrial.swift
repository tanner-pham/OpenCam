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
    var outcome: RawSizeCheckOutcome = .ran
    /// Why no capture was made; nil when one was.
    var skipReason: String?
    /// For an unsafe trial: the precondition that did not hold.
    var failedPrecondition: String?

    /// The size of the largest RAW picture ImageIO read from the DNG data.
    var measuredRawSize: RawSizeCheckSize? {
        capture?.photos.filter(\.isRaw).compactMap(\.size).max { $0.pixels < $1.pixels }
    }

    /// The resolved settings' RAW size, counted only when a RAW photo arrived (a timeout's resolved size is not a delivery).
    var resolvedRawSize: RawSizeCheckSize? {
        guard capture?.photos.contains(where: \.isRaw) == true else { return nil }
        return capture?.resolvedRawPhotoDimensions
    }

    /// The largest RAW this trial delivered: the DNG's measured size, or the resolved RAW size when ImageIO could not read the DNG.
    var deliveredRawSize: RawSizeCheckSize? { measuredRawSize ?? resolvedRawSize }
}
