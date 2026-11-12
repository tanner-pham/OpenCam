import AVFoundation

/// Picks the camera format for a size and rate: the highest bit depth the camera offers there, then one that supports HLG
/// BT.2020, then the format whose top frame rate is closest to the one asked for.
nonisolated enum RecorderCheckFormats {
    private static let tenBitSubTypes: Set<FourCharCode> = [
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_444YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange, kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange,
        kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange,
    ]

    static func bitDepth(ofSubType subType: FourCharCode) -> Int {
        tenBitSubTypes.contains(subType) ? 10 : 8
    }

    static func supports(_ format: AVCaptureDevice.Format, framesPerSecond: Int) -> Bool {
        let rate = Double(framesPerSecond)
        return format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= rate && rate <= $0.maxFrameRate }
    }

    static func colorSpaceName(_ space: AVCaptureColorSpace) -> String {
        switch space {
        case .sRGB: "sRGB"
        case .P3_D65: "P3_D65"
        case .HLG_BT2020: "HLG_BT2020"
        case .appleLog: "AppleLog"
        case .appleLog2: "AppleLog2"
        @unknown default: "unknown(\(space.rawValue))"
        }
    }

    static func pick(on device: AVCaptureDevice, for target: RecorderCheckTarget)
        -> (format: AVCaptureDevice.Format, pick: RecorderCheckFormatPick)? {
        let candidates = device.formats.filter { format in
            let size = format.formatDescription.dimensions
            return size.width == target.width && size.height == target.height && supports(format, framesPerSecond: target.framesPerSecond)
        }
        func topRate(_ format: AVCaptureDevice.Format) -> Double {
            format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        }
        func isBetter(_ lhs: AVCaptureDevice.Format, than rhs: AVCaptureDevice.Format) -> Bool {
            let leftDepth = bitDepth(ofSubType: lhs.formatDescription.mediaSubType.rawValue)
            let rightDepth = bitDepth(ofSubType: rhs.formatDescription.mediaSubType.rawValue)
            if leftDepth != rightDepth { return leftDepth > rightDepth }
            let leftHLG = lhs.supportedColorSpaces.contains(.HLG_BT2020), rightHLG = rhs.supportedColorSpaces.contains(.HLG_BT2020)
            if leftHLG != rightHLG { return leftHLG }
            let wanted = Double(target.framesPerSecond)
            return abs(topRate(lhs) - wanted) < abs(topRate(rhs) - wanted)
        }
        var best: AVCaptureDevice.Format?
        for candidate in candidates {
            guard let current = best else { best = candidate; continue }
            if isBetter(candidate, than: current) { best = candidate }
        }
        guard let best else { return nil }
        let subType = best.formatDescription.mediaSubType.rawValue
        let size = best.formatDescription.dimensions
        let pick = RecorderCheckFormatPick(
            cameraName: device.localizedName, cameraID: device.uniqueID,
            width: Int(size.width), height: Int(size.height),
            frameRateRanges: best.videoSupportedFrameRateRanges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" },
            mediaSubType: RecorderCheckFourCC.string(subType), bitDepthFromSubType: bitDepth(ofSubType: subType),
            supportedColorSpaces: best.supportedColorSpaces.map(colorSpaceName),
            isVideoBinned: best.isVideoBinned, isVideoHDRSupported: best.isVideoHDRSupported, candidateCount: candidates.count)
        return (best, pick)
    }
}
