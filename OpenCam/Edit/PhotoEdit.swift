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
        // ponytail: a new edit starts at the version its save stamps, so it equals itself read back. Changing masks
        // afterwards does not move it; nothing but a load reads it, and that only to spot a newer file.
        version = savedVersion
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

    /// Masks arrived in version 3. An edit without them is the shape version 2 builds read in full.
    static let versionWithoutMasks = 2

    /// The version a save stamps: the oldest that reads this edit in full, so a build from before masks keeps editing
    /// photos that have none and opens the rest read-only.
    var savedVersion: Int { masks.isEmpty ? Self.versionWithoutMasks : Self.currentVersion }
}
