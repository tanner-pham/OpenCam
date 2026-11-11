import Foundation

/// What one class of camera formats reported during the capability scan, as plain data.
nonisolated struct FormatDescriptor: Sendable, Equatable {
    let lensID: String
    let width: Int
    let height: Int
    let isBinned: Bool
    let frameRateRanges: [ClosedRange<Double>]
    /// Capture colour space raw value -> the movie output's `availableVideoCodecTypes` with that colour space active.
    let codecTypesByColourSpace: [Int: [String]]
    /// The movie output's `supportedOutputSettingsKeys(for:)` contains `AVVideoCompressionPropertiesKey`.
    let allowsCompressionProperties: Bool
    let maxPhotoDimensions: [PhotoSize]
    let hasBayerRAW: Bool
    /// The one size Bayer RAW is delivered at, when it is known: under the photo preset RAW comes at the preset format's own
    /// dimensions, and the processed half of a RAW + HEIF pair follows it (measured on the Duo, 2026-11-11). Nil offers RAW
    /// at every photo size, as the formats' own fields do without a preset reading.
    var rawPhotoSize: PhotoSize? = nil
}
