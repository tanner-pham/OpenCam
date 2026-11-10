import Foundation

nonisolated struct Lens: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let kind: LensKind
    let deviceUniqueID: String
    let zoomFactor: Double
    let label: String
}
