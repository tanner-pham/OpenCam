import Foundation

/// Turns scanned format descriptors into the options the interface offers.
nonisolated enum CapabilityMapper {
    /// Fixed-quality codecs by FourCC, in the order the Quality row lists them.
    private static let fixedCodecs: [(codecType: String, family: CodecFamily, quality: String)] = [
        ("aprn", .raw, "ProRes RAW"),
        ("aprh", .raw, "ProRes RAW HQ"),
        ("ap4x", .proRes, "4444 XQ"),
        ("ap4h", .proRes, "4444"),
        ("apch", .proRes, "422 HQ"),
        ("apcn", .proRes, "422"),
        ("apcs", .proRes, "422 LT"),
        ("apco", .proRes, "422 Proxy"),
    ]
    private static let tieredCodecs: [(codecType: String, family: CodecFamily)] = [("hvc1", .hevc), ("avc1", .h264)]
    private static let standardQuality = "Standard"

    /// Unknown FourCCs, and ones that are not video codecs here (`jpeg`, `jxlc`, `muxa`), are dropped.
    static func codecs(fourCCs: [String], allowsCompressionProperties: Bool) -> [VideoCodec] {
        fourCCs.flatMap { fourCC -> [VideoCodec] in
            if let fixed = fixedCodecs.first(where: { $0.codecType == fourCC }) {
                return [VideoCodec(family: fixed.family, quality: fixed.quality, codecType: fourCC, bitrateTier: nil)]
            }
            guard let tiered = tieredCodecs.first(where: { $0.codecType == fourCC }) else { return [] }
            guard allowsCompressionProperties else {
                return [VideoCodec(family: tiered.family, quality: standardQuality, codecType: fourCC, bitrateTier: nil)]
            }
            return BitrateTier.allCases.map { VideoCodec(family: tiered.family, quality: $0.rawValue, codecType: fourCC, bitrateTier: $0) }
        }
    }

    /// Every lens x codec x resolution x frame rate x colour the formats report, once each,
    /// grouped by lens in first-seen order, then in Record settings row order.
    static func videoOptions(from formats: [FormatDescriptor]) -> [VideoOption] {
        var seen = Set<VideoOption>()
        var options: [VideoOption] = []
        for format in formats {
            let resolution = Resolution.named(width: format.width, height: format.height)
            let rates = StandardFrameRates.collapse(format.frameRateRanges)
            for (rawColour, fourCCs) in format.codecTypesByColourSpace {
                guard let colour = ColourMode(captureColorSpace: rawColour) else { continue }
                for codec in codecs(fourCCs: fourCCs, allowsCompressionProperties: format.allowsCompressionProperties) {
                    for rate in rates {
                        let option = VideoOption(lensID: format.lensID, codec: codec, resolution: resolution, frameRate: rate, colour: colour)
                        if seen.insert(option).inserted { options.append(option) }
                    }
                }
            }
        }
        var lensOrder: [String] = []
        for option in options where !lensOrder.contains(option.lensID) { lensOrder.append(option.lensID) }
        return options.sorted { lhs, rhs in
            let left = (lensOrder.firstIndex(of: lhs.lensID) ?? 0, rowKey(lhs)), right = (lensOrder.firstIndex(of: rhs.lensID) ?? 0, rowKey(rhs))
            return left.0 != right.0 ? left.0 < right.0 : left.1.lexicographicallyPrecedes(right.1)
        }
    }

    /// One option per photo format per size for each lens. RAW only where the format has a Bayer RAW pixel format
    /// and the lens is not a zoomed crop of another (`zoomFactor` 1). A zoomed lens uses its camera's formats.
    static func photoOptions(from formats: [FormatDescriptor], lenses: [Lens]) -> [PhotoOption] {
        lenses.flatMap { lens -> [PhotoOption] in
            var seen = Set<PhotoOption>()
            var options: [PhotoOption] = []
            for format in descriptors(for: lens, lenses: lenses, in: formats) {
                let photoFormats = format.hasBayerRAW && lens.zoomFactor == 1 ? PhotoFormat.allCases : [.heif]
                for size in format.maxPhotoDimensions {
                    for photoFormat in photoFormats {
                        let option = PhotoOption(lensID: lens.id, format: photoFormat, width: size.width, height: size.height)
                        if seen.insert(option).inserted { options.append(option) }
                    }
                }
            }
            return options.sorted { lhs, rhs in
                lhs.width * lhs.height != rhs.width * rhs.height
                    ? lhs.width * lhs.height > rhs.width * rhs.height
                    : (PhotoFormat.allCases.firstIndex(of: lhs.format) ?? 0) < (PhotoFormat.allCases.firstIndex(of: rhs.format) ?? 0)
            }
        }
    }

    static func capabilities(lenses: [Lens], formats: [FormatDescriptor], osBuild: String, modelIdentifier: String) -> CaptureCapabilities {
        let video = lenses.flatMap { lens in
            videoOptions(from: descriptors(for: lens, lenses: lenses, in: formats)).map {
                VideoOption(lensID: lens.id, codec: $0.codec, resolution: $0.resolution, frameRate: $0.frameRate, colour: $0.colour)
            }
        }
        return CaptureCapabilities(lenses: lenses, videoOptions: video, photoOptions: photoOptions(from: formats, lenses: lenses),
                                   osBuild: osBuild, modelIdentifier: modelIdentifier)
    }

    /// The scan reads each camera once, under its unzoomed lens; a zoomed lens reuses that lens's descriptors.
    private static func descriptors(for lens: Lens, lenses: [Lens], in formats: [FormatDescriptor]) -> [FormatDescriptor] {
        let sourceID = lenses.first { $0.deviceUniqueID == lens.deviceUniqueID && $0.zoomFactor == 1 }?.id ?? lens.id
        return formats.filter { $0.lensID == sourceID }
    }

    /// Codec, quality, resolution (largest first), frame rate, colour.
    private static func rowKey(_ option: VideoOption) -> [Int] {
        [
            CodecFamily.allCases.firstIndex(of: option.codec.family) ?? CodecFamily.allCases.count,
            qualityRank(option.codec),
            -option.resolution.pixelCount,
            option.frameRate,
            ColourMode.allCases.firstIndex(of: option.colour) ?? ColourMode.allCases.count,
        ]
    }

    private static func qualityRank(_ codec: VideoCodec) -> Int {
        if let index = fixedCodecs.firstIndex(where: { $0.codecType == codec.codecType }) { return index }
        if let tier = codec.bitrateTier, let index = BitrateTier.allCases.firstIndex(of: tier) { return fixedCodecs.count + index }
        return fixedCodecs.count + BitrateTier.allCases.count
    }
}
