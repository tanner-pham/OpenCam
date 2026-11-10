import Foundation

/// Written as `OC_000n.json` beside each clip: what was asked for and what the file contains.
nonisolated struct ClipSidecar: Codable, Sendable {
    let requested: VideoOption
    /// Nil when the clip could not be read back.
    let actual: ClipFacts?
    let outcome: String
    let recordedAt: Date
    /// The recording or inspection error, for diagnosis; never shown on screen.
    let error: String?

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
