import Foundation

/// The remaining-time slot: its text and whether it takes the warning style.
nonisolated struct RemainingTime: Equatable, Sendable {
    let text: String
    let isWarning: Bool
}
