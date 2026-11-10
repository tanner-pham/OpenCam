import AVFoundation
import OSLog
import Synchronization

/// Owns the movie output and records one clip at a time. `start` is called on the `CameraSession` actor; the output
/// calls back on its own queue. After each clip it reads the file back, writes `OC_000n.json` beside it and yields the result.
/// Output settings are checked against what the output reports before they are set, because an invalid dictionary
/// raises an Objective-C exception Swift cannot catch (AVCaptureFileOutput.h, `setOutputSettings:forConnection:`).
nonisolated final class MovieRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "MovieRecorder")

    let output = AVCaptureMovieFileOutput()
    private let results: AsyncStream<RecordingResult>.Continuation
    /// The recording in flight, from `start` until the output reports its file finished.
    private let pending = Mutex<PendingRecording?>(nil)

    private struct PendingRecording: Sendable {
        let url: URL
        let option: VideoOption
        let recordedAt: Date
    }

    init(results: AsyncStream<RecordingResult>.Continuation) {
        self.results = results
        super.init()
    }

    /// `minFreeBytes` stops the recording when free space falls to it. The clip is rotated horizon-level, except
    /// ProRes RAW, which records unrotated (rotation is unsupported for RAW buffers, AVCaptureSession.h).
    func start(option: VideoOption, url: URL, minFreeBytes: Int64, device: AVCaptureDevice) throws(RecordingError) {
        guard !output.isRecording else { throw .alreadyRecording }
        guard let connection = output.connection(with: .video), connection.isActive else { throw .noVideoConnection }
        try applySettings(MovieOutputSettings.make(for: option, supportedKeys: output.supportedOutputSettingsKeys(for: connection)),
                          connection: connection)
        let angle = option.codec.family == .raw
            ? 0
            : AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil).videoRotationAngleForHorizonLevelCapture
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        output.minFreeDiskSpaceLimit = minFreeBytes
        pending.withLock { $0 = PendingRecording(url: url, option: option, recordedAt: Date()) }
        output.startRecording(to: url, recordingDelegate: self)
    }

    func stop() {
        guard output.isRecording else { return }
        output.stopRecording()
    }

    /// One level per channel of the output's audio connection; empty without a microphone.
    func audioLevels() -> [Double] {
        guard let connection = output.connection(with: .audio), connection.isActive else { return [] }
        return connection.audioChannels.map { AudioMeter.level(decibels: $0.averagePowerLevel) }
    }

    /// The codec must be one the output offers. The bitrate is added only when the compression properties the output
    /// reports for that codec include an average bitrate; otherwise the codec's default rate stands.
    private func applySettings(_ settings: MovieOutputSettings, connection: AVCaptureConnection) throws(RecordingError) {
        let codec = AVVideoCodecType(rawValue: settings.codecType)
        let available = output.availableVideoCodecTypes
        guard output.supportedOutputSettingsKeys(for: connection).contains(AVVideoCodecKey), available.contains(codec) else {
            throw .codecUnavailable(codec: settings.codecType, available: available.map(\.rawValue))
        }
        output.setOutputSettings([AVVideoCodecKey: codec], for: connection)
        guard let bitRate = settings.averageBitRate else { return }
        let compression = output.outputSettings(for: connection)[AVVideoCompressionPropertiesKey] as? [String: Any]
        guard compression?[AVVideoAverageBitRateKey] != nil else {
            Self.logger.info("[MovieRecorder:applySettings] Average bitrate not offered; codec default used — {codec: \(settings.codecType, privacy: .public)}")
            return
        }
        output.setOutputSettings([AVVideoCodecKey: codec, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate]], for: connection)
    }

    // MARK: AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        guard let recording = pending.withLock({ current -> PendingRecording? in
            defer { current = nil }
            return current
        }) else {
            Self.logger.error("[MovieRecorder:didFinishRecording] No recording was pending — {path: \(outputFileURL.path(percentEncoded: false), privacy: .public)}")
            return
        }
        let nsError = error.map { $0 as NSError }
        let outcome = RecordingOutcome(error: nsError)
        let message = nsError.map { "[MovieRecorder:didFinishRecording] Recording ended with an error — {domain: \($0.domain), code: \($0.code), playable: \(outcome.isPlayable)}" }
        if let message { Self.logger.error("\(message, privacy: .public)") }
        let results = self.results
        Task {
            results.yield(await Self.finish(recording, outcome: outcome, errorMessage: message))
        }
    }

    /// A clip the output called playable but that is missing is reported as failed; a clip that exists is never reported lost.
    private static func finish(_ recording: PendingRecording, outcome: RecordingOutcome, errorMessage: String?) async -> RecordingResult {
        let path = recording.url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            let failed: RecordingOutcome = outcome.isPlayable
                ? .failed("[MovieRecorder:finish] Clip missing after recording — {path: \(path)}")
                : outcome
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
        let errors = [errorMessage, inspectionError].compactMap { $0 }
        let sidecar = ClipSidecar(requested: recording.option, actual: actual, outcome: outcome.summary, recordedAt: recording.recordedAt,
                                  error: errors.isEmpty ? nil : errors.joined(separator: " "))
        let written = write(sidecar, beside: recording.url) ? sidecar : nil
        return RecordingResult(url: recording.url, option: recording.option, outcome: outcome, sidecar: written)
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
