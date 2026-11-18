import Foundation

/// The file `Documents/raw-size-check.json`.
nonisolated struct RawSizeCheckReport: Codable, Sendable, Equatable {
    var takenAt: Date
    var modelIdentifier: String
    var osVersion: String
    var osBuild: String
    var buildConfiguration: String
    var summary: RawSizeCheckSummary
    var isComplete: Bool
    var camerasChecked: [String]
    var skippedFormats: [RawSizeCheckSkippedFormats]
    var notes: [String]
    var errors: [String]
    var trials: [RawSizeCheckTrial]

    init(takenAt: Date, modelIdentifier: String, osVersion: String, osBuild: String, buildConfiguration: String, notes: [String]) {
        self.takenAt = takenAt
        self.modelIdentifier = modelIdentifier
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.buildConfiguration = buildConfiguration
        self.notes = notes
        summary = RawSizeCheckSummary.make(from: [])
        isComplete = false
        camerasChecked = []
        skippedFormats = []
        errors = []
        trials = []
    }

    /// The summary is always made from the trials, so it cannot disagree with them.
    mutating func refreshSummary() {
        summary = RawSizeCheckSummary.make(from: trials)
    }
}
