import AVFoundation
import CoreMedia
import CoreVideo

/// Receives the video frames and the sound of one trial and writes them to one asset writer, on the legacy path (add, readiness,
/// append, pixel buffer adaptor).
///
/// Threads: the video output delivers on the video queue and the audio output on the audio queue. Everything that touches the
/// writer, its inputs or the counters (the "writer state") runs inside `writerQueue.sync`, one serial queue for all writer work,
/// so a video append and an audio append never overlap and the counters are never raced. Work that belongs to the video side
/// alone (luma, the colour table render) runs on the video queue before it takes the writer queue, in `RecorderCheck2VideoStage`.
/// The audio callback waits on the writer queue behind a video append; that wait is part of what a one-writer recorder pays. The
/// object is not `Sendable`, the trial reads it only through `writerQueue.sync`.
///
/// All deprecated writer calls (iOS 27) sit in methods marked deprecated, so the build has no warnings.
nonisolated final class RecorderCheck2Sink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, RecorderCheck2WriterOpening {
    private let writerQueue: DispatchSerialQueue
    private let stage: RecorderCheck2VideoStage

    // Writer state: only inside writerQueue.sync.
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    @available(iOS, deprecated: 27.0)
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor? {
        get { adaptorStorage as? AVAssetWriterInputPixelBufferAdaptor }
        set { adaptorStorage = newValue }
    }
    private var adaptorStorage: AnyObject?
    private(set) var isVideoRealTimeConfirmed = false
    private var isStopped = false
    private var hasFailed = false
    private var hasAudioFailed = false
    private var counts = RecorderCheckSinkResult()
    private var audio = RecorderCheck2AudioFacts()
    private var firstDelivered: CMTime?
    private var lastDelivered: CMTime?
    private var firstAppended: CMTime?
    private var lastAppended: CMTime?
    private var appendTotal = Duration.zero
    private var appendWorst = Duration.zero
    private var appendCalls = 0

    init(writerQueue: DispatchSerialQueue, stage: RecorderCheck2VideoStage) {
        self.writerQueue = writerQueue
        self.stage = stage
        super.init()
    }

    @available(iOS, deprecated: 27.0, message: "Uses the legacy writer path on purpose; see the type's comment")
    func open(url: URL, videoSettings: [String: Any], audioSettings: [String: Any]?, adaptorFormat: (width: Int, height: Int, pixelFormat: OSType)?) throws -> String? {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw RecorderCheckFailure(message: "The writer could not be made: \(error.localizedDescription)")
        }
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw RecorderCheckFailure(message: "The writer refused the video settings (canApply was false)", isSettingsRejection: true)
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        isVideoRealTimeConfirmed = video.expectsMediaDataInRealTime
        guard writer.canAdd(video) else { throw RecorderCheckFailure(message: "The writer cannot take the video input") }
        writer.add(video)
        if let format = adaptorFormat {
            let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: format.pixelFormat,
                                             kCVPixelBufferWidthKey as String: format.width, kCVPixelBufferHeightKey as String: format.height]
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: attributes)
        }
        var audioNote: String?
        if let audioSettings {
            if !writer.canApply(outputSettings: audioSettings, forMediaType: .audio) {
                audioNote = "The writer refused the audio settings (canApply was false)"
            } else {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                input.expectsMediaDataInRealTime = true
                audio.inputExpectsRealTime = input.expectsMediaDataInRealTime
                if writer.canAdd(input) {
                    writer.add(input)
                    audioInput = input
                } else {
                    audioNote = "The writer cannot take the audio input"
                }
            }
        }
        do {
            try writer.start()
        } catch {
            throw RecorderCheckFailure(message: "start failed: \(RecorderCheckSink.statusName(writer.status)), \(error.localizedDescription)")
        }
        self.writer = writer
        videoInput = video
        return audioNote
    }

    @available(iOS, deprecated: 27.0, message: "Measures the deprecated append on purpose; see the type's comment")
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            writerQueue.sync { appendAudio(sampleBuffer) }
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        if let pixelBuffer { stage.noteLuma(of: pixelBuffer) }
        guard stage.usesColourPass else {
            writerQueue.sync { appendPlain(sampleBuffer, presentationTime: presentationTime) }
            return
        }
        guard writerQueue.sync(execute: { admit(sampleBuffer, presentationTime: presentationTime) }) else { return }
        guard let pixelBuffer, !stage.isBehind(presentationTime: presentationTime), let rendered = stage.render(pixelBuffer) else { return }
        writerQueue.sync { appendRendered(rendered, presentationTime: presentationTime) }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let reason = RecorderCheckSink.dropReason(of: sampleBuffer)
        writerQueue.sync {
            guard !isStopped else { return }
            counts.framesDroppedByOutput += 1
            counts.dropReasons[reason, default: 0] += 1
        }
    }

    // MARK: Writer state (call inside writerQueue.sync)

    /// Counts the frame, starts the session on the first one, and says whether it may be offered to the writer now.
    @available(iOS, deprecated: 27.0, message: "Uses the legacy writer path on purpose; see the type's comment")
    private func admit(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) -> Bool {
        guard !isStopped, let writer, let videoInput else { return false }
        counts.framesDelivered += 1
        if firstDelivered == nil {
            firstDelivered = presentationTime
            counts.firstFrame = RecorderCheckSink.facts(of: sampleBuffer)
            writer.startSession(atSourceTime: presentationTime)
        }
        lastDelivered = presentationTime
        guard !hasFailed else {
            counts.framesNotAppendedAfterWriterFailure += 1
            return false
        }
        guard videoInput.isReadyForMoreMediaData else {
            counts.framesNotAppendedInputNotReady += 1
            return false
        }
        return true
    }

    @available(iOS, deprecated: 27.0, message: "Measures the deprecated append on purpose; see the type's comment")
    private func appendPlain(_ sampleBuffer: CMSampleBuffer, presentationTime: CMTime) {
        guard admit(sampleBuffer, presentationTime: presentationTime), let videoInput else { return }
        let started = ContinuousClock.now
        let isAppended = videoInput.append(sampleBuffer)
        recordAppend(isAppended, elapsed: ContinuousClock.now - started, presentationTime: presentationTime)
    }

    @available(iOS, deprecated: 27.0, message: "Measures the deprecated append on purpose; see the type's comment")
    private func appendRendered(_ buffer: CVPixelBuffer, presentationTime: CMTime) {
        guard !isStopped, !hasFailed, let videoInput, let adaptor else { return }
        guard videoInput.isReadyForMoreMediaData else {
            counts.framesNotAppendedInputNotReady += 1
            return
        }
        let started = ContinuousClock.now
        let isAppended = adaptor.append(buffer, withPresentationTime: presentationTime)
        recordAppend(isAppended, elapsed: ContinuousClock.now - started, presentationTime: presentationTime)
    }

    private func recordAppend(_ isAppended: Bool, elapsed: Duration, presentationTime: CMTime) {
        appendTotal += elapsed
        appendWorst = max(appendWorst, elapsed)
        appendCalls += 1
        if isAppended {
            counts.framesAppended += 1
            firstAppended = firstAppended ?? presentationTime
            lastAppended = presentationTime
        } else {
            hasFailed = true
            let reason = writer?.error?.localizedDescription ?? "no error"
            counts.appendError = "append returned false: \(reason) (writer status \(writer.map { RecorderCheckSink.statusName($0.status) } ?? "none"))"
        }
    }

    @available(iOS, deprecated: 27.0, message: "Uses the legacy writer path on purpose; see the type's comment")
    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopped else { return }
        audio.buffersDelivered += 1
        guard let audioInput, !hasAudioFailed, !hasFailed else {
            audio.buffersNotAppendedOther += 1
            return
        }
        guard firstDelivered != nil else {
            audio.buffersNotAppendedBeforeVideoStart += 1
            return
        }
        guard audioInput.isReadyForMoreMediaData else {
            audio.buffersNotAppendedInputNotReady += 1
            return
        }
        if audioInput.append(sampleBuffer) {
            audio.buffersAppended += 1
        } else {
            hasAudioFailed = true
            audio.appendError = "audio append returned false: \(writer?.error?.localizedDescription ?? "no error")"
        }
    }

    var deliveredCount: Int { counts.framesDelivered }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
    }

    func beginFinishing(completion: @escaping @Sendable () -> Void) {
        guard let writer else {
            completion()
            return
        }
        guard firstDelivered != nil else {
            writer.cancelWriting()
            completion()
            return
        }
        writer.finishWriting(completionHandler: completion)
    }

    /// The video counts and the sound facts, once stopped and finished.
    func results() -> (video: RecorderCheckSinkResult, audio: RecorderCheck2AudioFacts) {
        var counts = counts
        counts.firstDeliveredPTS = firstDelivered?.seconds
        counts.lastDeliveredPTS = lastDelivered?.seconds
        counts.effectiveDeliveredFPS = Self.rate(frames: counts.framesDelivered, from: firstDelivered, to: lastDelivered)
        counts.firstAppendedPTS = firstAppended?.seconds
        counts.lastAppendedPTS = lastAppended?.seconds
        counts.effectiveAppendedFPS = Self.rate(frames: counts.framesAppended, from: firstAppended, to: lastAppended)
        counts.appendTotalMilliseconds = appendTotal.recorderCheckMilliseconds
        counts.appendWorstMilliseconds = appendWorst.recorderCheckMilliseconds
        counts.appendMeanMilliseconds = appendCalls == 0 ? nil : counts.appendTotalMilliseconds / Double(appendCalls)
        counts.writerStatus = writer.map { RecorderCheckSink.statusName($0.status) } ?? "not opened"
        counts.writerError = writer?.error.map { "\($0.localizedDescription) [\(String(describing: $0))]" }
        return (counts, audio)
    }

    private static func rate(frames: Int, from first: CMTime?, to last: CMTime?) -> Double? {
        guard frames > 1, let first, let last else { return nil }
        let span = (last - first).seconds
        return span > 0 ? Double(frames - 1) / span : nil
    }
}

/// The sink's state is confined to its queues; it is never shared across tasks.
@available(*, unavailable)
extension RecorderCheck2Sink: Sendable {}
