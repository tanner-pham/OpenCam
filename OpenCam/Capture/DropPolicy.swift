import Foundation

/// What the writer recorder does when a frame is missing from the file.
nonisolated enum DropPolicy: String, Codable, Sendable, CaseIterable {
    case keepRecording
    case stopRecording
}
