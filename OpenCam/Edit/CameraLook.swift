import Foundation

/// The look the camera applies: a copy of a saved look's id, name and adjustments, so the selection survives a relaunch
/// and the camera needs nothing else to apply it.
nonisolated struct CameraLook: Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var adjustments: Adjustments

    init(id: UUID, name: String, adjustments: Adjustments) {
        self.id = id
        self.name = name
        self.adjustments = adjustments
    }

    init(_ look: Look) {
        self.init(id: look.id, name: look.name, adjustments: look.adjustments)
    }

    /// nil when `selected` is nil or no look in `looks` has its id; otherwise that look's current name and adjustments.
    static func reconciled(_ selected: CameraLook?, with looks: [Look]) -> CameraLook? {
        guard let selected, let look = looks.first(where: { $0.id == selected.id }) else { return nil }
        return CameraLook(look)
    }
}
