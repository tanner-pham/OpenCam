import Foundation

/// Everything the recorder check found. Written to `Documents/recorder-check.json` after every section and every trial
/// (`isComplete` false) and once more at the end (`isComplete` true).
nonisolated struct RecorderCheckReport: Codable, Sendable {
    var schemaVersion = 1
    var takenAt: Date
    var isComplete = false
    /// "Debug" or "Release".
    var buildConfiguration: String
    var notes: [String]
    var device: RecorderCheckDeviceFacts
    var stateAtStart: RecorderCheckSnapshot?
    var stateAtEnd: RecorderCheckSnapshot?
    /// Section names, in the order they finished.
    var completedSections: [String] = []
    /// A: what the data output offers per size and rate.
    var dataOutputOffers: [RecorderCheckOffer] = []
    /// A: what the data output offers on the photo preset.
    var photoPresetOffer: RecorderCheckPresetOffer?
    /// B: the writer trials, in the order they were meant to run.
    var writerTrials: [RecorderCheckTrialResult] = []
    /// B: why the trials stopped before the last one, if they did.
    var writerTrialsStoppedEarly: String?
    /// C: RAW photo cadence.
    var rawCadence: RecorderCheckRawCadence?
    /// Every error the run logged, in the house format.
    var errors: [String] = []
}
