import Foundation

/// The options only the writer records, derived in memory from the scan's HLG formats and never cached. A 10-bit format is
/// HLG only, so "this lens has an HEVC option in HLG at this size and rate" is the proof of a 10-bit format there.
nonisolated enum WriterOptions {
    static let maximumFrameRate = 60

    private static let proResFourCCs = ["apch", "apcn", "apcs", "apco"]

    /// The one place a measured limit goes. True for everything up to 60 fps today.
    static func isOffered(quality: String, resolution: Resolution, frameRate: Int, colour: ColourMode) -> Bool {
        frameRate <= maximumFrameRate
    }

    /// Options only the writer records, grouped by lens in the mapper's row order; none the scan already holds.
    static func derived(from scanned: [VideoOption], support: WriterSupport) -> [VideoOption] {
        guard !support.isEmpty else { return [] }
        let proRes = CapabilityMapper.codecs(fourCCs: proResFourCCs, allowsCompressionProperties: false)
        let held = Set(scanned)

        struct Key: Hashable {
            let lensID: String
            let resolution: Resolution
            let frameRate: Int
        }
        // One pass: the HEVC HLG codecs and the HEVC Rec. 709 keys, per lens, size and rate.
        var hlgCodecs: [Key: [VideoCodec]] = [:]
        var hasRec709: Set<Key> = []
        var lensOrder: [String] = []
        var seenLens: Set<String> = []
        for option in scanned {
            if seenLens.insert(option.lensID).inserted { lensOrder.append(option.lensID) }
            guard option.codec.family == .hevc else { continue }
            let key = Key(lensID: option.lensID, resolution: option.resolution, frameRate: option.frameRate)
            switch option.colour {
            case .hlg: hlgCodecs[key, default: []].append(option.codec)
            case .rec709: hasRec709.insert(key)
            default: break
            }
        }

        var derived: [VideoOption] = []
        func add(_ key: Key, _ codecs: [VideoCodec], _ colour: ColourMode) {
            for codec in codecs where isOffered(quality: codec.quality, resolution: key.resolution, frameRate: key.frameRate, colour: colour) {
                let option = VideoOption(lensID: key.lensID, codec: codec, resolution: key.resolution, frameRate: key.frameRate, colour: colour)
                if !held.contains(option) { derived.append(option) }
            }
        }
        for (key, hevcCodecs) in hlgCodecs where key.frameRate <= maximumFrameRate {
            if support.contains(.proRes) { add(key, proRes, .hlg) }
            if support.contains(.log) {
                add(key, proRes, .log)
                add(key, hevcCodecs, .log)
            }
            if support.contains(.proResSDR), hasRec709.contains(key) { add(key, proRes, .rec709) }
        }
        let order = Dictionary(uniqueKeysWithValues: lensOrder.enumerated().map { ($1, $0) })
        return derived.sorted { lhs, rhs in
            let left = order[lhs.lensID] ?? 0, right = order[rhs.lensID] ?? 0
            return left != right ? left < right : CapabilityMapper.rowKey(lhs).lexicographicallyPrecedes(CapabilityMapper.rowKey(rhs))
        }
    }
}
