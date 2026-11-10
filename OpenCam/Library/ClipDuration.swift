import AVFoundation
import Foundation
import OSLog

nonisolated enum ClipDuration {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "ClipDuration")

    /// The sidecar's recorded duration, else the file's own; nil when neither reads.
    @concurrent static func seconds(of item: LibraryItem) async -> Double? {
        if let sidecarURL = item.sidecarURL {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let sidecar = try decoder.decode(ClipSidecar.self, from: Data(contentsOf: sidecarURL))
                if let seconds = sidecar.actual?.durationSeconds, seconds.isFinite, seconds >= 0 { return seconds }
            } catch {
                logger.error("[ClipDuration:seconds] Cannot read the sidecar — {path: \(sidecarURL.path(percentEncoded: false), privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            }
        }
        do {
            let duration = try await AVURLAsset(url: item.pictureURL).load(.duration).seconds
            return duration.isFinite && duration >= 0 ? duration : nil
        } catch {
            logger.error("[ClipDuration:seconds] Cannot read the clip — {path: \(item.pictureURL.path(percentEncoded: false), privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return nil
        }
    }
}
