import Foundation

/// The mode, lens, video and photo choices that survive a relaunch.
nonisolated struct SavedSelections: Codable, Sendable, Equatable {
    static let key = "savedSelections"

    var mode: CaptureMode
    var lensID: String
    var record: RecordSelection
    var photo: PhotoSelection
    /// The look the camera applies; nil is None. Absent from selections saved before looks existed.
    var look: CameraLook? = nil

    static func load(from defaults: UserDefaults) -> SavedSelections? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedSelections.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
