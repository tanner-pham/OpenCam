import Foundation

/// The edit of one photo: its adjustments and the name of the look they were copied from, if any.
nonisolated struct PhotoEdit: Codable, Sendable, Equatable {
    static let currentVersion = 3
    var adjustments = Adjustments()
    var lookName: String? = nil
    var masks: [LocalMask] = []
    var version = PhotoEdit.currentVersion

    init(adjustments: Adjustments = Adjustments(), lookName: String? = nil, masks: [LocalMask] = []) {
        self.adjustments = adjustments
        self.lookName = lookName
        self.masks = masks
    }

    private enum CodingKeys: String, CodingKey { case adjustments, lookName, masks, version }

    /// Missing adjustments are the identity, a missing version is 1, and unknown keys are ignored.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        adjustments = try container.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? Adjustments()
        lookName = try container.decodeIfPresent(String.self, forKey: .lookName)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        // A file from a newer build may hold masks this one cannot read; it opens read-only, so skip them rather than fail.
        do { masks = try container.decodeIfPresent([LocalMask].self, forKey: .masks) ?? [] } catch where version > PhotoEdit.currentVersion { masks = [] }
    }

    /// Masks are written only when there are some, so an edit without them reads as before.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(adjustments, forKey: .adjustments)
        try container.encodeIfPresent(lookName, forKey: .lookName)
        if !masks.isEmpty { try container.encode(masks, forKey: .masks) }
        try container.encode(version, forKey: .version)
    }

    var isIdentity: Bool { adjustments.isIdentity && lookName == nil && masks.isEmpty }
}
