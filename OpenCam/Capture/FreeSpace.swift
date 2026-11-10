import Foundation
import OSLog

/// Free space on the volume that holds the captures.
nonisolated enum FreeSpace {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "FreeSpace")

    /// `volumeAvailableCapacityForImportantUsage` of Documents; 0 when it cannot be read (logged).
    static func availableBytes() -> Int64 {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("[FreeSpace:availableBytes] Documents folder not found — {directory: documentDirectory}")
            return 0
        }
        do {
            let values = try documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            logger.error("[FreeSpace:availableBytes] Cannot read free space — {path: \(documents.path(percentEncoded: false), privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return 0
        }
    }
}
