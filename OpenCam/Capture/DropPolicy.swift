import Foundation

/// What the writer recorder does when a frame is missing from the file.
nonisolated enum DropPolicy: String, Codable, Sendable, CaseIterable {
    case keepRecording
    case stopRecording
}

nonisolated extension DropPolicy {
    static let rowTitle = "When frames drop"
    private static let defaultsKey = "dropPolicy"

    var title: String {
        switch self {
        case .keepRecording: "Keep recording"
        case .stopRecording: "Stop recording"
        }
    }

    /// The one line under the setting. The system recorder has no live drop signal, so the policy acts on the writer path only.
    static func line(_ policy: DropPolicy, recorder: RecorderPath) -> String {
        switch (recorder, policy) {
        case (.system, _): "This format is checked for dropped frames when the clip ends. It does not stop early."
        case (.writer, .keepRecording): "Dropped frames are counted on screen and saved with the clip."
        case (.writer, .stopRecording): "Recording stops at the first dropped frame. The clip is saved."
        }
    }

    /// `keepRecording` when nothing, or something unknown, is saved.
    static func load(from defaults: UserDefaults) -> DropPolicy {
        defaults.string(forKey: defaultsKey).flatMap(DropPolicy.init(rawValue:)) ?? .keepRecording
    }

    func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
