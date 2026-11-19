import Foundation

/// How the combined back camera shows one lens: the camera to attach and the zoom on it.
nonisolated struct CombinedLens: Codable, Sendable, Equatable {
    let deviceUniqueID: String
    let zoomFactor: Double
}
