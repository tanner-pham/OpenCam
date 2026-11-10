import Foundation

/// One line the picture area shows in place of a picture, with an Open Settings button when Settings can fix it.
nonisolated struct ViewfinderStatus: Equatable, Sendable {
    let message: String
    let offersSettings: Bool
}
