import Foundation

/// The edit of one photo: its adjustments and the name of the look they were copied from, if any.
nonisolated struct PhotoEdit: Codable, Sendable, Equatable {
    static let currentVersion = 2
    var adjustments = Adjustments()
    var lookName: String? = nil
    var version = PhotoEdit.currentVersion

    init(adjustments: Adjustments = Adjustments(), lookName: String? = nil) {
        self.adjustments = adjustments
        self.lookName = lookName
    }

    private enum CodingKeys: String, CodingKey { case adjustments, lookName, version }

    /// Missing adjustments are the identity, a missing version is 1, and unknown keys are ignored.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        adjustments = try container.decodeIfPresent(Adjustments.self, forKey: .adjustments) ?? Adjustments()
        lookName = try container.decodeIfPresent(String.self, forKey: .lookName)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    var isIdentity: Bool { adjustments.isIdentity && lookName == nil }
}
