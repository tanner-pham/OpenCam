import Foundation

/// Written as `Documents/Captures/sweep-<date>.json` when a format sweep ends or is cancelled.
nonisolated struct SweepReport: Codable, Sendable {
    let startedAt: Date
    let finishedAt: Date
    let lensID: String
    let osBuild: String
    let modelIdentifier: String
    let cancelled: Bool
    let rows: [SweepRow]

    /// "sweep-2026-11-09-143005.json", from `date` in `timeZone`.
    static func fileName(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "sweep-\(formatter.string(from: date)).json"
    }

    /// "80 passed, 4 failed."
    var summary: String {
        let passed = rows.count { $0.status == .pass }
        return "\(passed) passed, \(rows.count - passed) failed."
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
