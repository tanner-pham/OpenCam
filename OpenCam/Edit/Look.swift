import Foundation

/// A named, saved set of adjustments.
nonisolated struct Look: Codable, Sendable, Equatable, Identifiable {
    static let currentVersion = 2
    let id: UUID
    var name: String
    var adjustments: Adjustments
    let createdAt: Date
    var version = Look.currentVersion

    init(id: UUID, name: String, adjustments: Adjustments, createdAt: Date) {
        self.id = id
        self.name = name
        self.adjustments = adjustments
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, adjustments, createdAt, version }

    /// A missing version is 1 and unknown keys are ignored.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        adjustments = try container.decode(Adjustments.self, forKey: .adjustments)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}
