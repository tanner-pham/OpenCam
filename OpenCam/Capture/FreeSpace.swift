import Foundation
import OSLog

/// Free space on the volume that holds the captures.
nonisolated enum FreeSpace {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "FreeSpace")

    /// `volumeAvailableCapacityForImportantUsage` of Documents; 0 when it cannot be read (logged). Callers that must tell a failed
    /// read from a full disk use `readBytes()`.
    static func availableBytes() -> Int64 {
        readBytes() ?? 0
    }

    /// The same figure, nil when it cannot be read (logged).
    static func readBytes() -> Int64? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("[FreeSpace:readBytes] Documents folder not found — {directory: documentDirectory}")
            return nil
        }
        do {
            let values = try documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage
        } catch {
            logger.error("[FreeSpace:readBytes] Cannot read free space — {path: \(documents.path(percentEncoded: false), privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return nil
        }
    }
}
