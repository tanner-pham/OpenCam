import Foundation

/// Where the check keeps its files: the report in Documents, everything else in a scratch folder in the temporary directory.
nonisolated enum RecorderCheckStore {
    static let fileName = "recorder-check.json"

    static var scratchDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "recorder-check", directoryHint: .isDirectory)
    }

    /// An empty scratch folder; leftovers of a run that crashed are removed first.
    static func resetScratch() throws {
        try? FileManager.default.removeItem(at: scratchDirectory)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    }

    static func removeScratch() {
        try? FileManager.default.removeItem(at: scratchDirectory)
    }

    static func write(_ report: RecorderCheckReport) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try encoder.encode(report).write(to: directory.appending(path: fileName), options: .atomic)
    }
}
