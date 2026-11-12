import Foundation

/// The configuration the last run confirmed, kept whole so the next launch can start the session from it before any
/// capability is read. `SavedSelections` is not enough: a `SessionConfiguration` holds a whole lens and format options.
/// The record is used only when it is exactly what this launch would resolve (`configuration(for:...)`).
nonisolated struct SavedStart: Codable, Sendable, Equatable {
    static let key = "savedStart"

    var configuration: SessionConfiguration
    /// What `configuration` was resolved from.
    var record: RecordSelection
    var photo: PhotoSelection
    /// Of the capabilities it was resolved against.
    var osBuild: String
    var modelIdentifier: String
    var scanVersion: Int

    static func load(from defaults: UserDefaults) -> SavedStart? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedStart.self, from: data)
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }

    /// The configuration to start with, or nil when anything this launch would resolve differs from what was saved.
    func configuration(for saved: SavedSelections?, access: CaptureAccess, hasLook: Bool,
                       osBuild: String, modelIdentifier: String) -> SessionConfiguration? {
        // The cache's own rule: the same OS build, device and scan.
        guard self.osBuild == osBuild, self.modelIdentifier == modelIdentifier, scanVersion == CaptureCapabilities.currentScanVersion else { return nil }
        // The selection saved now; the look's content is not compared, only whether frames are drawn.
        guard let saved, saved.mode == configuration.mode, saved.lensID == configuration.lens.id,
              saved.record == record, saved.photo == photo else { return nil }
        guard access.camera == .authorized, access.microphone != .notDetermined, configuration.includesAudio == access.recordsSound else { return nil }
        guard configuration.needsFrames == (hasLook && LookAvailability.isOffered(mode: configuration.mode, colour: record.colour, recorder: configuration.recorder)) else { return nil }
        return configuration
    }
}
