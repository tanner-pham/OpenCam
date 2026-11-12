import AVFoundation
import CoreMedia
import OSLog
import Synchronization

/// Owns the `AVAssetWriter` of one clip at a time and its `WriterClipState`, which makes every decision (first frame, drops, the
/// stop policy, how the clip ends); this class carries the decisions out.
///
/// Threads: the video output delivers on the video queue and the audio output on the audio queue. Everything that touches the
/// writer, its inputs or the clip state runs inside `writerQueue.sync`, so a video append and an audio append never overlap and
/// the state is never raced. The delegate callbacks read the clock and the drop reason, then enter the writer queue; the sample
/// buffer never leaves the callback. The writer queue never waits on any other queue, and what leaves it are `@Sendable`
/// closures that start a `Task`. Every member below is called inside `writerQueue.sync`, except the delegate callbacks, which
/// enter it themselves. The object is not `Sendable`.
///
/// iOS 27 deprecates `add`, `startWriting`, an input's `isReadyForMoreMediaData` and `expectsMediaDataInRealTime`, and `append`,
/// in favour of an input receiver that wants a `CMReadySampleBuffer`, which the camera's `CMSampleBuffer` cannot become without
/// an opt-out the project bans. The calls sit in members marked deprecated, which callers reach through the non-deprecated
/// protocols `WriterOpening` and `WriterAppending`, so the build has no warning. The pattern ran on the phone in the diagnostic
/// (20 trials, no frame dropped).
nonisolated final class WriterSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, WriterOpening {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "WriterSink")
    /// A fragment every 10 seconds, so a file the writer could not finish plays up to its last fragment (AVAssetWriter.h).
    private static let fragmentInterval = CMTime(value: 10, timescale: 1)
    /// AAC 48 kHz stereo 128 kb/s, as in the diagnostic, for when the output recommends nothing.
    private static var fallbackAudioSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000]
    }

    private enum Phase {
        case idle, recording
        /// The clip has ended and the file is being finished; its report is not read yet.
        case finishing
    }

    /// Counts clips, so a finish reported late for an earlier clip is not taken for the current one.
    private nonisolated final class Generation: Sendable {
        let value = Mutex(0)
    }

    private let writerQueue: DispatchSerialQueue
    private let onDrops: @Sendable (Int) -> Void
    private let onFinished: @Sendable () -> Void
    /// Fixed at creation, so any queue can read the clock against it.
    private let origin = ContinuousClock.now
    private let generation = Generation()

    // Writer state: only inside writerQueue.sync.
    private var phase = Phase.idle
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var frameDuration = CMTime(value: 1, timescale: 30)
    private var state: WriterClipState?
    private var errorText: String?
    private var recommendedVideo: [String: Any]?
    private var recommendedAudio: [String: Any]?

    /// `onDrops` receives the running total of frames missing from the clip. `onFinished` runs once per clip, when its file is
    /// finished (or cancelled), on an arbitrary thread; it must only start a `Task`.
    init(writerQueue: DispatchSerialQueue, onDrops: @escaping @Sendable (Int) -> Void, onFinished: @escaping @Sendable () -> Void) {
        self.writerQueue = writerQueue
        self.onDrops = onDrops
        self.onFinished = onFinished
        super.init()
    }

    // MARK: Delegates

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let arrival = ContinuousClock.now - origin
        if output is AVCaptureAudioDataOutput {
            writerQueue.sync { receiveAudio(sampleBuffer) }
        } else {
            writerQueue.sync { receiveVideo(sampleBuffer, arrival: arrival) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let arrival = ContinuousClock.now - origin
        let attachment = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil) as? String
        let reason = DropReason(attachment: attachment)
        writerQueue.sync { receiveDrop(reason, arrival: arrival) }
    }

    // MARK: Opening

    /// What the outputs recommend for the next clip, read on the session's queue; consumed by the next `open`. Without them the
    /// settings are built here: codec, width and height (ProRes), and the sound as AAC 48 kHz stereo 128 kb/s.
    func recommend(video: [String: Any]?, audio: [String: Any]?) {
        recommendedVideo = video
        recommendedAudio = audio
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func open(_ plan: WriterClipPlan, recordsSound: Bool) throws(RecordingError) {
        guard phase == .idle else { throw .alreadyRecording }
        let recommendedVideo = recommendedVideo, recommendedAudio = recommendedAudio
        self.recommendedVideo = nil
        self.recommendedAudio = nil
        func refusal(_ reason: String) -> RecordingError { .writerNotOpened(codec: plan.codecType, reason: reason) }
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: plan.url, fileType: .mov)
        } catch {
            throw refusal("the writer could not be made: \(error.localizedDescription)")
        }
        writer.movieFragmentInterval = Self.fragmentInterval
        let videoSettings = Self.videoSettings(for: plan, recommended: recommendedVideo)
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw refusal("the writer refused the video settings")
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        // The picture is turned by the track, so no buffer is rotated.
        video.transform = CGAffineTransform(rotationAngle: CGFloat(plan.rotationDegrees * .pi / 180))
        guard writer.canAdd(video) else { throw refusal("the writer cannot take the video input") }
        writer.add(video)
        var audio: AVAssetWriterInput?
        if recordsSound {
            let settings = recommendedAudio ?? Self.fallbackAudioSettings
            guard writer.canApply(outputSettings: settings, forMediaType: .audio) else { throw refusal("the writer refused the sound settings") }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw refusal("the writer cannot take the sound input") }
            writer.add(input)
            audio = input
        }
        do {
            try writer.start()
        } catch {
            throw refusal("the writer did not start: \(error.localizedDescription)")
        }
        self.writer = writer
        videoInput = video
        audioInput = audio
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, plan.frameRate)))
        state = WriterClipState(policy: plan.policy, frameDuration: frameDuration, minFreeBytes: plan.minFreeBytes)
        errorText = nil
        phase = .recording
        generation.value.withLock { $0 += 1 }
    }

    /// The recommended settings when the output gave them (HEVC), else codec, width and height. Neither carries a colour
    /// properties key, so the file is tagged from the frames (AVVideoSettings.h). The tier's bit rate is added to the compression
    /// properties.
    private static func videoSettings(for plan: WriterClipPlan, recommended: [String: Any]?) -> [String: Any] {
        var settings = recommended ?? [AVVideoCodecKey: plan.codecType, AVVideoWidthKey: plan.width, AVVideoHeightKey: plan.height]
        settings[AVVideoColorPropertiesKey] = nil
        if let bitRate = plan.averageBitRate {
            var compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any] ?? [:]
            compression[AVVideoAverageBitRateKey] = bitRate
            settings[AVVideoCompressionPropertiesKey] = compression
        }
        return settings
    }

    // MARK: Frames

    /// A video frame arrived `arrival` after the sink was made.
    func receiveVideo(_ sampleBuffer: CMSampleBuffer, arrival: Duration) {
        guard phase == .recording else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var duration = CMSampleBufferGetDuration(sampleBuffer)
        if !duration.isNumeric || CMTimeCompare(duration, .zero) <= 0 {
            duration = frameDuration
        }
        let io: any WriterAppending = self
        let isReady = videoInput != nil && io.isVideoReady()
        guard let step = state?.video(pts: pts, duration: duration, arrival: arrival, isWriterReady: isReady) else { return }
        switch step {
        case .ignore:
            return
        case .skip:
            // A drop found here can end the clip under "Stop recording".
            if let finish = state?.takePendingFinish() { carryOut(finish) }
        case .startAndWrite(let time):
            writer?.startSession(atSourceTime: time)
            append(sampleBuffer, pts: pts, duration: duration)
        case .write:
            append(sampleBuffer, pts: pts, duration: duration)
        }
        reportDrops(arrival: arrival)
    }

    func receiveAudio(_ sampleBuffer: CMSampleBuffer) {
        guard phase == .recording, audioInput != nil else { return }
        let io: any WriterAppending = self
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard state?.audio(pts: pts, isWriterReady: io.isAudioReady()) == true else { return }
        if !io.appendAudio(sampleBuffer) {
            note("[WriterSink:receiveAudio] A sound buffer was not appended — \(writerDetail())")
        }
    }

    /// The output's drop callback.
    func receiveDrop(_ reason: DropReason, arrival: Duration) {
        guard phase == .recording, let finish = state?.outputDropped(reason) else { return }
        carryOut(finish)
        reportDrops(arrival: arrival)
    }

    func storage(freeBytes: Int64) {
        guard phase == .recording, let finish = state?.storage(freeBytes: freeBytes) else { return }
        carryOut(finish)
    }

    // MARK: Ending

    /// Ends the clip for `end`; the first end stands. Returns whether a clip is in flight: recording, or ended with its report
    /// not read yet.
    func end(_ end: WriterEnd) -> Bool {
        guard phase != .idle else { return false }
        if let finish = state?.end(end) { carryOut(finish) }
        return true
    }

    /// The report of an ended clip, once; then the sink is idle. Nil while the clip still records or when none is in flight.
    /// `timedOut` reads it before the writer reported it finished: the end is then `.timedOut`, and the writer's late finish is
    /// ignored. The file stays either way.
    func takeReport(timedOut: Bool = false) -> WriterReport? {
        guard phase != .idle, let state, let end = state.end else { return nil }
        var text = errorText
        if let writer, writer.status == .failed {
            let failure = "[WriterSink:takeReport] The writer failed — {status: failed, error: \(writer.error.map { String(describing: $0) } ?? "none")}"
            Self.logger.error("\(failure, privacy: .public)")
            text = [text, failure].compactMap { $0 }.joined(separator: " ")
        }
        let report = WriterReport(end: timedOut ? .timedOut : end, facts: state.facts, hasFrames: state.facts.framesWritten > 0, errorText: text)
        phase = .idle
        self.state = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        generation.value.withLock { $0 += 1 }
        return report
    }

    /// True from `open` until the report is taken.
    var isInFlight: Bool { phase != .idle }

    // MARK: Private

    private func append(_ sampleBuffer: CMSampleBuffer, pts: CMTime, duration: CMTime) {
        let io: any WriterAppending = self
        let isWritten = io.appendVideo(sampleBuffer)
        if !isWritten {
            note("[WriterSink:receiveVideo] A video frame was not appended — \(writerDetail())")
        }
        if let finish = state?.videoWritten(isWritten, pts: pts, duration: duration) { carryOut(finish) }
    }

    private func reportDrops(arrival: Duration) {
        if let total = state?.dropCountToReport(arrival: arrival) { onDrops(total) }
    }

    private func carryOut(_ finish: WriterClipState.Finish) {
        switch finish {
        case .none:
            return
        case .cancel:
            cancel()
        case .finish(let endTime):
            finishFile(at: endTime)
        }
    }

    /// Both inputs are finished and the session ends at the last written frame, while the writer is still writing, so sound past
    /// the last frame is edited out (AVAssetWriter.h). All appends have returned: they share this queue.
    private func finishFile(at endTime: CMTime) {
        phase = .finishing
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        guard let writer else {
            onFinished()
            return
        }
        if writer.status == .writing { writer.endSession(atSourceTime: endTime) }
        let token = generation.value.withLock { $0 }
        let generation = generation
        let notify = onFinished
        writer.finishWriting {
            if generation.value.withLock({ $0 }) == token { notify() }
        }
    }

    /// Only for a clip with no frame written: nothing is lost, and the empty file is removed.
    private func cancel() {
        phase = .finishing
        writer?.cancelWriting()
        onFinished()
    }

    private func writerDetail() -> String {
        "{status: \(writer.map { String(describing: $0.status.rawValue) } ?? "none"), error: \(writer?.error.map { String(describing: $0) } ?? "none")}"
    }

    private func note(_ text: String) {
        Self.logger.error("\(text, privacy: .public)")
        errorText = [errorText, text].compactMap { $0 }.joined(separator: " ")
    }
}

extension WriterSink: WriterAppending {
    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func isVideoReady() -> Bool {
        videoInput?.isReadyForMoreMediaData ?? false
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func isAudioReady() -> Bool {
        audioInput?.isReadyForMoreMediaData ?? false
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func appendVideo(_ sampleBuffer: CMSampleBuffer) -> Bool {
        videoInput?.append(sampleBuffer) ?? false
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func appendAudio(_ sampleBuffer: CMSampleBuffer) -> Bool {
        audioInput?.append(sampleBuffer) ?? false
    }
}

/// The sink's state is confined to its writer queue; it is never shared across tasks.
@available(*, unavailable)
extension WriterSink: Sendable {}
