import Foundation
import OSLog

/// What the clip screen says about a clip: a one-line summary and the rows of the "Clip info" sheet, from the clip's sidecar.
nonisolated struct ClipInfo: Sendable, Equatable {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "ClipInfo")

    /// "HEVC High · 4K · 30 fps · HLG"; `LibraryCopy.noClipDetails` without a sidecar.
    let summary: String
    /// Empty without a sidecar.
    let rows: [PhotoInfoRow]

    init(sidecar: ClipSidecar?) {
        guard let sidecar else {
            summary = LibraryCopy.noClipDetails
            rows = []
            return
        }
        let requested = sidecar.requested, actual = sidecar.actual
        let resolution = actual.map { Resolution.named(width: $0.width, height: $0.height) } ?? requested.resolution
        let size = resolution.label == resolution.detail ? resolution.detail : "\(resolution.label), \(resolution.detail)"
        let frameRate = Self.frameRateText(actual?.nominalFrameRate ?? Double(requested.frameRate))
        let colour = (actual?.colour ?? requested.colour).shortName
        let codec = requested.codec.displayName
        var rows = [PhotoInfoRow(title: "Codec", value: codec), PhotoInfoRow(title: "Size", value: size),
                    PhotoInfoRow(title: "Frame rate", value: frameRate), PhotoInfoRow(title: "Colour", value: colour)]
        if let actual {
            rows.append(PhotoInfoRow(title: "Data rate", value: Self.dataRateText(megabitsPerSecond: actual.megabitsPerSecond)))
            rows.append(PhotoInfoRow(title: "Duration", value: LibraryCopy.duration(seconds: actual.durationSeconds)))
            rows.append(PhotoInfoRow(title: "Sound", value: actual.hasAudio ? "Yes" : "No"))
        }
        if let dropped = sidecar.drops?.total ?? actual?.droppedFrames {
            rows.append(PhotoInfoRow(title: "Dropped frames", value: dropped == 0 ? "None" : String(dropped)))
        }
        self.rows = rows
        summary = [codec, resolution.label, frameRate, colour].joined(separator: " · ")
    }

    /// Reads the item's sidecar; a missing or unreadable one gives `init(sidecar: nil)`, and an unreadable one is logged.
    @concurrent static func load(for item: LibraryItem) async -> ClipInfo {
        guard let url = item.sidecarURL else { return ClipInfo(sidecar: nil) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return ClipInfo(sidecar: try decoder.decode(ClipSidecar.self, from: Data(contentsOf: url)))
        } catch {
            logger.error("[ClipInfo:load] Cannot read the sidecar — {path: \(url.path(percentEncoded: false), privacy: .public), reason: \(error.localizedDescription, privacy: .public)}")
            return ClipInfo(sidecar: nil)
        }
    }

    /// 30 is "30 fps", 29.97 is "29.97 fps", 59.94006 is "59.94 fps".
    static func frameRateText(_ fps: Double) -> String {
        let rounded = (fps * 100).rounded() / 100
        return rounded == rounded.rounded() ? "\(Int(rounded)) fps" : "\(rounded) fps"
    }

    /// From 10 up, whole: "148 Mb/s". Below, one decimal: "6.2 Mb/s".
    static func dataRateText(megabitsPerSecond: Double) -> String {
        let tenths = (megabitsPerSecond * 10).rounded() / 10
        return tenths >= 10 ? "\(Int(megabitsPerSecond.rounded())) Mb/s" : "\(tenths) Mb/s"
    }
}
