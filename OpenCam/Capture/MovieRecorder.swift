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
    /// The recording in flight, from `start` until the output reports its file finished, and the finished files still
    /// being read back before their result is yielded.
    private let inFlight = InFlight()

    /// One lock over both, so a clip is never seen as neither pending nor finishing between the two.
    private nonisolated final class InFlight: Sendable {
        private struct State: Sendable {
            var pending: PendingRecording?
            var finishing = 0
        }

        private let state = Mutex(State())

        /// True from `begin` until `reported`.
        var isAwaitingResult: Bool { state.withLock { $0.pending != nil || $0.finishing > 0 } }

        /// Replaces any earlier pending recording, whose end was never reported.
        func begin(_ recording: PendingRecording) {
            state.withLock { $0.pending = recording }
        }

        /// The pending recording, now finishing; nil when none was pending.
        func finish() -> PendingRecording? {
            state.withLock { current in
                guard let pending = current.pending else { return nil }
                current.pending = nil
                current.finishing += 1
                return pending
            }
        }

        func reported() {
            state.withLock { $0.finishing -= 1 }
        }
    }

    private struct PendingRecording: Sendable {
        let url: URL
        let option: VideoOption
        let recordedAt: Date
        let onFinish: @Sendable () -> Void
    }

    init(results: AsyncStream<RecordingResult>.Continuation) {
        self.results = results
        super.init()
    }

    /// `minFreeBytes` stops the recording when free space falls to it. The clip is rotated horizon-level, except
    /// ProRes RAW, which records unrotated (rotation is unsupported for RAW buffers, AVCaptureSession.h).
    /// `onFinish` runs on the output's queue as soon as the file is finished, however the recording ended; not when this throws.
    func start(option: VideoOption, url: URL, minFreeBytes: Int64, device: AVCaptureDevice,
               onFinish: @escaping @Sendable () -> Void) throws(RecordingError) {
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
        inFlight.begin(PendingRecording(url: url, option: option, recordedAt: Date(), onFinish: onFinish))
        output.startRecording(to: url, recordingDelegate: self)
    }

    /// Stops the clip being recorded. Returns whether a clip is in flight: recording, started and not yet reported
    /// finished, or finished with its result still to come. False means no result will follow.
    @discardableResult
    func stop() -> Bool {
        guard output.isRecording else { return inFlight.isAwaitingResult }
        output.stopRecording()
        return true
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
        guard let recording = inFlight.finish() else {
            Self.logger.error("[MovieRecorder:didFinishRecording] No recording was pending — {path: \(outputFileURL.path(percentEncoded: false), privacy: .public)}")
            return
        }
        recording.onFinish()
        let nsError = error.map { $0 as NSError }
        let outcome = RecordingOutcome(error: nsError)
        let message = nsError.map { "[MovieRecorder:didFinishRecording] Recording ended with an error — {domain: \($0.domain), code: \($0.code), playable: \(outcome.isPlayable)}" }
        if let message { Self.logger.error("\(message, privacy: .public)") }
        let results = self.results
        let inFlight = self.inFlight
        Task {
            results.yield(await Self.finish(recording, outcome: outcome, errorMessage: message))
            inFlight.reported()
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
