import Foundation
import OSLog

/// What happens to a clip once its file is finished, for either recorder: read it back, write `OC_000n.json` beside it, and
/// return the result. Moved out of `MovieRecorder` so the writer recorder ends a clip the same way.
nonisolated enum ClipFinisher {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "ClipFinisher")

    /// A clip the recorder called playable but that is missing is reported as failed; a clip that exists is never reported lost.
    /// `outcome` is asked once, after the file was read back, and receives whether the file has a video track longer than zero
    /// (false when the file is missing or cannot be read).
    static func finish(_ recording: PendingRecording, recorder: RecorderPath, drops: DropFacts?, errorMessage: String?,
                       outcome: @Sendable (_ isReadable: Bool) -> RecordingOutcome) async -> RecordingResult {
        let path = recording.url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            let reported = outcome(false)
            let failed: RecordingOutcome = reported.isPlayable
                ? .failed("[ClipFinisher:finish] Clip missing after recording — {path: \(path)}")
                : reported
            if case .failed(let message) = failed { logger.error("\(message, privacy: .public)") }
            return RecordingResult(url: recording.url, option: recording.option, outcome: failed, sidecar: nil)
        }
        var actual: ClipFacts?
        var inspectionError: String?
        do throws(RecordingError) {
            actual = try await ClipInspector.inspect(url: recording.url, requestedFrameRate: recording.option.frameRate)
        } catch {
            inspectionError = error.description
            logger.error("\(error.description, privacy: .public)")
        }
        let isReadable = actual.map { $0.durationSeconds > 0 } ?? false
        let finished = outcome(isReadable)
        let errors = [errorMessage, inspectionError].compactMap { $0 }
        let sidecar = ClipSidecar(requested: recording.option, actual: actual, outcome: finished.summary, recordedAt: recording.recordedAt,
                                  error: errors.isEmpty ? nil : errors.joined(separator: " "), recorder: recorder, drops: drops)
        let written = write(sidecar, beside: recording.url) ? sidecar : nil
        return RecordingResult(url: recording.url, option: recording.option, outcome: finished, sidecar: written)
    }

    /// `OC_0002.MOV` gets `OC_0002.json`.
    private static func write(_ sidecar: ClipSidecar, beside clip: URL) -> Bool {
        let url = clip.deletingPathExtension().appendingPathExtension(CaptureFileKind.sidecar.rawValue)
        do {
            try sidecar.encoded().write(to: url, options: .atomic)
            return true
        } catch {
            let failure = RecordingError.cannotWriteSidecar(path: url.path(percentEncoded: false), reason: error.localizedDescription)
            logger.error("\(failure.description, privacy: .public)")
            return false
        }
    }
}
