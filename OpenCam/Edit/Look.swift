import Foundation

/// A named, saved set of adjustments.
nonisolated struct Look: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var adjustments: Adjustments
    let createdAt: Date
}
