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
}
