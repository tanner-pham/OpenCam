import Foundation

/// Everything the second recorder check found; written to `Documents/recorder-check-2.json` after every trial and at the end.
nonisolated struct RecorderCheck2Report: Codable, Sendable {
    var schemaVersion = 1
    var takenAt: Date
    var isComplete = false
    var buildConfiguration: String
    var notes: [String]
    var device: RecorderCheckDeviceFacts
    var stateAtStart: RecorderCheckSnapshot?
    var stateAtEnd: RecorderCheckSnapshot?
    var trials: [RecorderCheck2TrialResult] = []
    /// Why the trials stopped before the last one, if they did.
    var trialsStoppedEarly: String?
    var errors: [String] = []
}
