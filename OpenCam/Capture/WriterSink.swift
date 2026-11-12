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

    /// Says that one writer's completion handler has run.
    private nonisolated final class Completion: Sendable {
        let isDone = Mutex(false)
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
    private var outputURL: URL?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    /// The adaptor of a clip whose frames are rendered. Held as `AnyObject` so the deprecated type appears only in the witnesses.
    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor? {
        get { adaptorStorage as? AVAssetWriterInputPixelBufferAdaptor }
        set { adaptorStorage = newValue }
    }
    private var adaptorStorage: AnyObject?
    /// The render stage of a clip that bakes its frames; nil otherwise. Read only inside the writer queue, used on the video queue.
    private var render: RecordingRender?
    private var frameDuration = CMTime(value: 1, timescale: 30)
    private var state: WriterClipState?
    private var errorText: String?
    private var completion = Completion()
    /// Writers whose clip was reported as timed out before their completion handler ran. They stay alive until it has, and their
    /// file is not read before then.
    private var lingering: [(writer: AVAssetWriter, completion: Completion)] = []
    /// Why the sound input was left out of the clip just opened (the writer refused its settings); nil when it was added or not asked for.
    private(set) var soundRefusal: String?
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
            return
        }
        // A clip that bakes its frames takes three steps: admit on the writer queue, render here on the video queue (the writer
        // queue stays free for sound), then append on the writer queue. The callback does not return before the last, so at
        // most the frame in hand is held; a late frame is refused in the first step, before it costs a render.
        guard let job = writerQueue.sync(execute: { routeVideo(sampleBuffer, arrival: arrival) }) else { return }
        let rendered = CMSampleBufferGetImageBuffer(sampleBuffer).flatMap { job.render.render($0) }
        writerQueue.sync { receiveRendered(rendered, pts: job.pts, duration: job.duration) }
    }

    /// What the video queue renders: the render stage of this clip and the frame's times.
    private struct RenderJob {
        let render: RecordingRender
        let pts: CMTime
        let duration: CMTime
    }

    /// Inside the writer queue. A clip that does not bake takes the frame here, whole; one that does admits it and hands back the
    /// render stage (read here, so the property is only touched inside the queue). Nil: nothing more to do for this frame.
    private func routeVideo(_ sampleBuffer: CMSampleBuffer, arrival: Duration) -> RenderJob? {
        guard let render else {
            receiveVideo(sampleBuffer, arrival: arrival)
            return nil
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = normalisedDuration(CMSampleBufferGetDuration(sampleBuffer))
        return admitVideo(pts: pts, duration: duration, arrival: arrival) ? RenderJob(render: render, pts: pts, duration: duration) : nil
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
        lingering.removeAll { $0.completion.isDone.withLock { $0 } }
        soundRefusal = nil
        let recommendedVideo = recommendedVideo, recommendedAudio = recommendedAudio
        self.recommendedVideo = nil
        self.recommendedAudio = nil
        func refusal(_ reason: String) -> RecordingError { .writerNotOpened(codec: plan.codecType, reason: reason) }
        // A clip that cannot be rendered fails here, before any writer or file exists.
        var stage: RecordingRender?
        if plan.bakesLog {
            let candidate = RecordingRender(cube: LogProfile.bakeCube())
            guard candidate.prepare(width: plan.width, height: plan.height) else {
                throw refusal("the Log render could not be set up for \(plan.width) x \(plan.height) frames")
            }
            stage = candidate
        }
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
        var newAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        if plan.bakesLog {
            let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: RecordingRender.pixelFormat,
                                             kCVPixelBufferWidthKey as String: plan.width, kCVPixelBufferHeightKey as String: plan.height]
            newAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: attributes)
        }
        var audio: AVAssetWriterInput?
        if recordsSound {
            let settings = recommendedAudio ?? Self.fallbackAudioSettings
            // Sound the writer will not take never fails the recording: the clip is made without it and the caller says so.
            if !writer.canApply(outputSettings: settings, forMediaType: .audio) {
                soundRefusal = "[WriterSink:open] The writer refused the sound settings — {codec: \(plan.codecType)}"
            } else {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                if writer.canAdd(input) {
                    writer.add(input)
                    audio = input
                } else {
                    soundRefusal = "[WriterSink:open] The writer cannot take the sound input — {codec: \(plan.codecType)}"
                }
            }
        }
        do {
            try writer.start()
        } catch {
            throw refusal("the writer did not start: \(error.localizedDescription)")
        }
        self.writer = writer
        outputURL = plan.url
        videoInput = video
        audioInput = audio
        adaptor = newAdaptor
        render = stage
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, plan.frameRate)))
        state = WriterClipState(policy: plan.policy, frameDuration: frameDuration, minFreeBytes: plan.minFreeBytes,
                               rendersFrames: plan.bakesLog)
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
        let duration = normalisedDuration(CMSampleBufferGetDuration(sampleBuffer))
        // A writer that stopped by itself never calls `append` again (its input is not ready), so without this the clip would
        // run on, every frame a "not ready" drop, until the user stopped it.
        if endIfWriterStopped() { return }
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

    /// Step one for a clip that bakes its frames: counts the frame, starts the session on the first, and says whether to render it.
    /// False for a frame the writer is not ready for, or that is more than one frame behind (counted as a drop, and the "Stop
    /// recording" policy may end the clip here), and for any frame once the clip has ended.
    func admitVideo(pts: CMTime, duration: CMTime, arrival: Duration) -> Bool {
        guard phase == .recording else { return false }
        if endIfWriterStopped() { return false }
        let io: any WriterAppending = self
        let isReady = videoInput != nil && io.isVideoReady()
        guard let step = state?.video(pts: pts, duration: duration, arrival: arrival, isWriterReady: isReady) else { return false }
        switch step {
        case .ignore:
            return false
        case .skip:
            if let finish = state?.takePendingFinish() { carryOut(finish) }
            reportDrops(arrival: arrival)
            return false
        case .startAndWrite(let time):
            writer?.startSession(atSourceTime: time)
            return true
        case .write:
            return true
        }
    }

    /// Step three: appends the rendered frame through the adaptor. A frame that did not render (nil) is a counted `renderFailed`
    /// drop, and so is a writer that stopped being ready while it rendered; either can end the clip under "Stop recording".
    func receiveRendered(_ buffer: CVPixelBuffer?, pts: CMTime, duration: CMTime) {
        guard phase == .recording else { return }
        let arrival = ContinuousClock.now - origin
        if endIfWriterStopped() { return }
        let io: any WriterAppending = self
        if let buffer, io.isVideoReady() {
            let isWritten = io.appendVideo(buffer, at: pts)
            if !isWritten {
                note("[WriterSink:receiveRendered] A rendered frame was not appended — \(writerDetail())")
            }
            if let finish = state?.videoWritten(isWritten, pts: pts, duration: duration) { carryOut(finish) }
        } else {
            let finish = buffer == nil ? state?.renderFailed() : state?.outputDropped(.writerNotReady)
            if let finish { carryOut(finish) }
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

    /// A reading that could not be taken (nil) never ends the clip; one at or under the minimum does.
    func storage(freeBytes: Int64?) {
        guard phase == .recording else { return }
        // A camera that delivers no frames still gets to notice a writer that stopped.
        if endIfWriterStopped() { return }
        guard let freeBytes, let finish = state?.storage(freeBytes: freeBytes) else { return }
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
        lingering.removeAll { $0.completion.isDone.withLock { $0 } }
        if timedOut, let writer, !completion.isDone.withLock({ $0 }) { lingering.append((writer, completion)) }
        let report = WriterReport(end: timedOut ? .timedOut : end, facts: state.facts, hasFrames: state.facts.framesWritten > 0, errorText: text)
        phase = .idle
        self.state = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptorStorage = nil
        render = nil
        generation.value.withLock { $0 += 1 }
        return report
    }

    /// True from `open` until the report is taken.
    var isInFlight: Bool { phase != .idle }

    /// True once the clip has ended and its file is being finished.
    var isFinishing: Bool { phase == .finishing }

    /// Whether the clip just opened has a sound input.
    var hasSoundInput: Bool { audioInput != nil }

    // MARK: Private

    /// Ends the clip as `.writerFailed` when the writer is no longer writing (failed, or cancelled from outside), keeping its error
    /// text for the report. Returns whether it did.
    private func endIfWriterStopped() -> Bool {
        guard phase == .recording, let writer, writer.status != .writing else { return false }
        note("[WriterSink:endIfWriterStopped] The writer stopped by itself — {status: \(writer.status.rawValue), error: \(writer.error.map { String(describing: $0) } ?? "none")}")
        if let finish = state?.end(.writerFailed) { carryOut(finish) }
        return true
    }

    /// The writer, for tests that make it fail from outside. Read inside the writer queue.
    var currentWriter: AVAssetWriter? { writer }

    /// A buffer's own duration, or the frame time when it has none.
    private func normalisedDuration(_ duration: CMTime) -> CMTime {
        duration.isNumeric && CMTimeCompare(duration, .zero) > 0 ? duration : frameDuration
    }

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
        // `finishWriting` on a writer that is not writing raises an exception Swift cannot catch (measured in the Simulator with a
        // cancelled writer, status 4), and a failed one has nothing left to finish: it is reported as it is, and the file it
        // wrote stays.
        guard let writer, writer.status == .writing else {
            onFinished()
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.endSession(atSourceTime: endTime)
        let token = generation.value.withLock { $0 }
        let generation = generation
        let notify = onFinished
        let done = Completion()
        completion = done
        writer.finishWriting {
            done.isDone.withLock { $0 = true }
            if generation.value.withLock({ $0 }) == token { notify() }
        }
    }

    /// Only for a clip with no frame written: nothing is lost, and the empty file is removed. A writer that already failed leaves
    /// `cancelWriting` with nothing to do, so the file it may have left is removed here.
    private func cancel() {
        phase = .finishing
        writer?.cancelWriting()
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
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
    func appendVideo(_ pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        adaptor?.append(pixelBuffer, withPresentationTime: time) ?? false
    }

    @available(iOS, deprecated: 27.0, message: "Uses the writer calls iOS 27 deprecates on purpose; see the type's comment")
    func appendAudio(_ sampleBuffer: CMSampleBuffer) -> Bool {
        audioInput?.append(sampleBuffer) ?? false
    }
}

/// The sink's state is confined to its writer queue; it is never shared across tasks.
@available(*, unavailable)
extension WriterSink: Sendable {}
