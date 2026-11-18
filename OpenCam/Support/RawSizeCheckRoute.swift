/// The four ways the check asks for a RAW photo.
nonisolated enum RawSizeCheckRoute: String, Codable, Sendable, CaseIterable {
    case photoPreset = "A"
    case proRAW = "B"
    case chosenFormat = "C"
    case rawWithCompanion = "D"

    /// "Route C", for the summary sentence.
    var shortTitle: String { "Route \(rawValue)" }
}
