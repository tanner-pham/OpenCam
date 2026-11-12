import Foundation

nonisolated struct Chip: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let isAvailable: Bool
    let reason: String?
    /// The data rate and record time a tap on this chip would give; only Codec and Quality chips carry one.
    var estimate: ChipEstimate? = nil
}

/// Two short lines for a chip, and the same facts in words for VoiceOver.
nonisolated struct ChipEstimate: Equatable, Sendable {
    let rate: String
    let time: String
    let spoken: String
}
