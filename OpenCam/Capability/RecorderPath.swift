import Foundation

/// Which recorder writes a clip: the system movie output, or the writer recorder (ProRes and the baked Log profile).
nonisolated enum RecorderPath: String, Codable, Sendable {
    case system, writer
}
