import Foundation

/// What one camera offers under the photo preset.
nonisolated struct PhotoPresetReading: Sendable, Equatable {
    var width: Int                 // the preset's active format
    var height: Int
    var sizes: [PhotoSize]         // that format's supportedMaxPhotoDimensions
    var hasBayerRAW: Bool

    /// The descriptors of one lens with their photo fields replaced by the reading: every descriptor loses its photo
    /// sizes and RAW flag, except one carrier (the first whose dimensions equal the reading's, else the first), which
    /// takes the reading's sizes and RAW flag, with RAW limited to the reading's own format dimensions (`rawPhotoSize`), the
    /// only size the preset delivers it at. With a nil reading, or no descriptors, they come back unchanged.
    static func assign(_ reading: PhotoPresetReading?, to descriptors: [FormatDescriptor]) -> [FormatDescriptor] {
        guard let reading, !descriptors.isEmpty else { return descriptors }
        let carrier = descriptors.firstIndex { $0.width == reading.width && $0.height == reading.height } ?? 0
        return descriptors.enumerated().map { index, descriptor in
            let isCarrier = index == carrier
            return FormatDescriptor(
                lensID: descriptor.lensID,
                width: descriptor.width,
                height: descriptor.height,
                isBinned: descriptor.isBinned,
                frameRateRanges: descriptor.frameRateRanges,
                codecTypesByColourSpace: descriptor.codecTypesByColourSpace,
                allowsCompressionProperties: descriptor.allowsCompressionProperties,
                maxPhotoDimensions: isCarrier ? reading.sizes : [],
                hasBayerRAW: isCarrier && reading.hasBayerRAW,
                rawPhotoSize: isCarrier ? PhotoSize(width: reading.width, height: reading.height) : nil
            )
        }
    }
}
