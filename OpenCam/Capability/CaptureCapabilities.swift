import Foundation

nonisolated struct CaptureCapabilities: Codable, Sendable, Equatable {
    var lenses: [Lens]
    var videoOptions: [VideoOption]
    var photoOptions: [PhotoOption]
    var osBuild: String
    var modelIdentifier: String
    /// Discovered lenses the scan could not read; they are left out of `lenses` until a rescan.
    var skippedLensIDs: [String] = []
    /// How the scan that made these was taken. A file without it was written before the photo preset reading, and
    /// decodes as 1; the cache reuses only `currentScanVersion`.
    var scanVersion: Int = CaptureCapabilities.currentScanVersion
    /// Options only the writer records, derived from the scan in memory. Never encoded or decoded: the cache holds the scan alone.
    var writerOptions: [VideoOption] = []

    private enum CodingKeys: String, CodingKey {
        case lenses, videoOptions, photoOptions, osBuild, modelIdentifier, skippedLensIDs, scanVersion
    }

    static let fixtureName = "CapabilitiesFixture"
    /// 2: photo sizes and RAW come from each camera under the photo preset.
    /// 3: RAW and RAW + HEIF only at the preset format's own size, the one size the preset delivers RAW at.
    static let currentScanVersion = 3

    static func bundledFixture(in bundle: Bundle = .main) throws(CapabilityError) -> CaptureCapabilities {
        guard let url = bundle.url(forResource: fixtureName, withExtension: "json") else {
            throw .fixtureMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(path: url.path, reason: String(describing: error))
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws(CapabilityError) -> CaptureCapabilities {
        do {
            return try JSONDecoder().decode(CaptureCapabilities.self, from: data)
        } catch {
            throw .unreadable(path: "(data)", reason: String(describing: error))
        }
    }

    func encoded() throws(CapabilityError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(self)
        } catch {
            throw .unwritable(path: "(data)", reason: String(describing: error))
        }
    }

    /// These capabilities with the writer options `support` allows, derived from the scanned options.
    func withWriterOptions(_ support: WriterSupport) -> CaptureCapabilities {
        var merged = self
        merged.writerOptions = WriterOptions.derived(from: videoOptions, support: support)
        return merged
    }

    func videoOptions(forLens id: String) -> [VideoOption] {
        videoOptions.filter { $0.lensID == id }
    }

    func photoOptions(forLens id: String) -> [PhotoOption] {
        photoOptions.filter { $0.lensID == id }
    }

    /// These capabilities with the freshly discovered lenses for the ids they cover (labels can carry localized names),
    /// or nil when one of their lenses was not discovered. Skipped lenses do not make a miss, so a camera that could not
    /// be read is not rescanned on every launch; a rescan is asked for explicitly.
    func adopting(discovered lenses: [Lens]) -> CaptureCapabilities? {
        let ids = Set(self.lenses.map(\.id))
        let current = lenses.filter { ids.contains($0.id) }
        guard !current.isEmpty, current.count == ids.count else { return nil }
        var adopted = self
        adopted.lenses = current
        return adopted
    }
}

nonisolated extension CaptureCapabilities {
    /// `skippedLensIDs` and `scanVersion` are optional in the file, so the bundled fixture and caches written before they
    /// existed still load; a missing `scanVersion` is 1.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(lenses: try container.decode([Lens].self, forKey: .lenses),
                  videoOptions: try container.decode([VideoOption].self, forKey: .videoOptions),
                  photoOptions: try container.decode([PhotoOption].self, forKey: .photoOptions),
                  osBuild: try container.decode(String.self, forKey: .osBuild),
                  modelIdentifier: try container.decode(String.self, forKey: .modelIdentifier),
                  skippedLensIDs: try container.decodeIfPresent([String].self, forKey: .skippedLensIDs) ?? [],
                  scanVersion: try container.decodeIfPresent(Int.self, forKey: .scanVersion) ?? 1)
    }
}
