import Foundation

/// Where the editor stands: still loading, showing the photo, or showing a sentence instead of it.
nonisolated enum EditorPhase: Equatable, Sendable {
    case loading, ready, failed(String)
}
