import Foundation

nonisolated struct Chip: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let isAvailable: Bool
    let reason: String?
}
