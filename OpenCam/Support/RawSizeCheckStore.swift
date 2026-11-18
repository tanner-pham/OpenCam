import Foundation

/// Where the check keeps its report. Photos are measured in memory, so there is nothing else to keep or delete.
nonisolated enum RawSizeCheckStore {
    static let fileName = "raw-size-check.json"

    static func encode(_ report: RawSizeCheckReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    static func write(_ report: RawSizeCheckReport) throws {
        let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try encode(report).write(to: directory.appending(path: fileName), options: .atomic)
    }
}
