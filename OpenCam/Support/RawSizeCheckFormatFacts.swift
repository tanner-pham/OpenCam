import AVFoundation

/// A camera format, as the check reports it.
nonisolated struct RawSizeCheckFormatFacts: Codable, Sendable, Equatable {
    var width: Int
    var height: Int
    var mediaSubType: String
    var supportedMaxPhotoDimensions: [RawSizeCheckSize]
    var isHighestPhotoQualitySupported: Bool
    var maxFramesPerSecond: Int

    init(width: Int, height: Int, mediaSubType: String, supportedMaxPhotoDimensions: [RawSizeCheckSize], isHighestPhotoQualitySupported: Bool,
         maxFramesPerSecond: Int) {
        self.width = width
        self.height = height
        self.mediaSubType = mediaSubType
        self.supportedMaxPhotoDimensions = supportedMaxPhotoDimensions
        self.isHighestPhotoQualitySupported = isHighestPhotoQualitySupported
        self.maxFramesPerSecond = maxFramesPerSecond
    }

    init(_ format: AVCaptureDevice.Format) {
        let size = format.formatDescription.dimensions
        width = Int(size.width)
        height = Int(size.height)
        mediaSubType = RawSizeCheckFourCC.string(format.formatDescription.mediaSubType.rawValue)
        supportedMaxPhotoDimensions = format.supportedMaxPhotoDimensions.map(RawSizeCheckSize.init)
        isHighestPhotoQualitySupported = format.isHighestPhotoQualitySupported
        maxFramesPerSecond = Int(format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
    }

    /// For the summary sentence and the report.
    var description: String {
        let sizes = supportedMaxPhotoDimensions.map(\.label).joined(separator: ", ")
        return "\(width)x\(height) \(mediaSubType) up to \(maxFramesPerSecond) fps (photo sizes \(sizes), highest photo quality \(isHighestPhotoQualitySupported ? "yes" : "no"))"
    }
}
