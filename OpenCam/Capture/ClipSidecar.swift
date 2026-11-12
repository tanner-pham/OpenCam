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
    /// Which recorder wrote the clip. Nil in sidecars written before the writer recorder existed.
    let recorder: RecorderPath?
    /// What the writer counted for the clip; nil for the system recorder and for older sidecars.
    let drops: DropFacts?

    init(requested: VideoOption, actual: ClipFacts?, outcome: String, recordedAt: Date, error: String?,
         recorder: RecorderPath? = nil, drops: DropFacts? = nil) {
        self.requested = requested
        self.actual = actual
        self.outcome = outcome
        self.recordedAt = recordedAt
        self.error = error
        self.recorder = recorder
        self.drops = drops
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
