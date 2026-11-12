import AVFoundation
import CoreMedia
import CoreVideo
import Synchronization

/// Owns the writer path's two data outputs, the three queues and the `WriterSink`. Called on the session actor, which owns it;
/// neither it nor the sink is `Sendable`.
///
/// Queues: the actor (`opencam.session`) attaches, starts, ends and collects. `opencam.record.video` and `opencam.record.audio`
/// are the outputs' delegate queues. `opencam.record.writer` is the only queue that touches the writer, its inputs and the clip
/// state; the other three enter it with `sync`, and it never waits on any of them.
nonisolated final class WriterRecorder {
    let videoOutput = AVCaptureVideoDataOutput()
    let audioOutput = AVCaptureAudioDataOutput()

    private let videoQueue = DispatchSerialQueue(label: "opencam.record.video", qos: .userInitiated)
    private let audioQueue = DispatchSerialQueue(label: "opencam.record.audio", qos: .userInitiated)
    private let writerQueue = DispatchSerialQueue(label: "opencam.record.writer", qos: .userInitiated)
    private let sink: WriterSink
    private let results: AsyncStream<RecordingResult>.Continuation
    private let events: AsyncStream<SessionEvent>.Continuation
    private let shared: Shared
    /// The clip recording, until its report is collected. Actor-confined.
    private var pending: PendingRecording?

    /// What the sink's closures and the finishing tasks read from any thread.
    private nonisolated final class Shared: Sendable {
        /// `CaptureStore.clipKey` of the clip recording, which the drop count is reported for.
        let clipKey = Mutex("")
        /// Clips whose report was collected and whose result is still being made.
        let finishing = Mutex(0)
    }

    /// `onFinished` runs once per clip, when its file is finished, on an arbitrary thread; it must only start a `Task`
    /// that calls `collect()` on the owner.
    init(results: AsyncStream<RecordingResult>.Continuation, events: AsyncStream<SessionEvent>.Continuation,
         onFinished: @escaping @Sendable () -> Void) {
        let shared = Shared()
        self.shared = shared
        self.results = results
        self.events = events
        sink = WriterSink(writerQueue: writerQueue, onDrops: { total in
            events.yield(.framesDropped(clip: shared.clipKey.withLock { $0 }, total: total))
        }, onFinished: onFinished)
        // Full-size frames, none thrown away to keep up: a frame the writer is not ready for is counted as a drop instead.
        // Must be turned off before deliversPreviewSizedOutputBuffers can be set (AVCaptureVideoDataOutput.h).
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.automaticallyConfiguresOutputBufferDimensions = false
        videoOutput.deliversPreviewSizedOutputBuffers = false
    }

    /// The pixel format a colour records from: 10-bit 4:2:0 `x420` for HLG and Log (the camera's 10-bit formats are HLG only),
    /// 8-bit `420v` for Rec. 709 and P3. Nil for the colours the writer path does not record.
    static func pixelFormat(for colour: ColourMode) -> OSType? {
        switch colour {
        case .hlg, .log: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        case .rec709, .p3: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case .appleLog, .appleLog2: nil
        }
    }

    /// Asks the output for the colour's pixel format. Call after the camera's format is set. False when the output does not offer it.
    func preparePixelFormat(for colour: ColourMode) -> Bool {
        guard let format = Self.pixelFormat(for: colour), videoOutput.availableVideoPixelFormatTypes.contains(format) else { return false }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
        return true
    }

    /// Opens the writer for `option` and starts taking frames. The frames are the active format's size and are not rotated: the
    /// track carries the horizon-level rotation. Throws before taking any frame; a failed start leaves nothing recording.
    func start(option: VideoOption, url: URL, minFreeBytes: Int64, policy: DropPolicy, device: AVCaptureDevice, recordsSound: Bool) throws(RecordingError) {
        guard !isClipInFlight else { throw .alreadyRecording }
        guard let connection = videoOutput.connection(with: .video), connection.isActive else { throw .noVideoConnection }
        let dimensions = device.activeFormat.formatDescription.dimensions
        let angle = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil).videoRotationAngleForHorizonLevelCapture
        let plan = WriterClipPlan.make(option: option, url: url, bufferWidth: Int(dimensions.width), bufferHeight: Int(dimensions.height),
                                       rotationDegrees: Double(angle), policy: policy, minFreeBytes: minFreeBytes)
        // The Log profile is baked frame by frame by the sink. A clip whose render cannot be set up is refused by the sink's open,
        // before any writer exists, and a frame that arrives in another format than the render's is counted as a failed render.
        var video: [String: Any]?
        if option.codec.family != .proRes {
            // Asking for settings of a codec the output does not list raises an exception (AVCaptureVideoDataOutput.h).
            let codec = AVVideoCodecType(rawValue: plan.codecType)
            let available = videoOutput.availableVideoCodecTypesForAssetWriter(writingTo: .mov)
            guard available.contains(codec) else {
                throw .writerNotOpened(codec: plan.codecType, reason: "the camera output does not offer this codec for a movie file, it offers \(available.map(\.rawValue).joined(separator: ","))")
            }
            video = videoOutput.recommendedVideoSettings(forVideoCodecType: codec, assetWriterOutputFileType: .mov)
        }
        let audio = recordsSound ? audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) : nil
        shared.clipKey.withLock { $0 = CaptureStore.clipKey(for: url) }
        var soundRefusal: String?
        var hasSound = false
        do {
            try writerQueue.sync {
                sink.recommend(video: video, audio: audio)
                let opening: any WriterOpening = sink
                try opening.open(plan, recordsSound: recordsSound)
                soundRefusal = sink.soundRefusal
                hasSound = sink.hasSoundInput
            }
        } catch let error as RecordingError {
            throw error
        } catch {
            throw .writerNotOpened(codec: plan.codecType, reason: String(describing: error))
        }
        pending = PendingRecording(url: url, option: option, recordedAt: Date(), onFinish: {})
        // Set only while a clip records.
        videoOutput.setSampleBufferDelegate(sink, queue: videoQueue)
        if hasSound { audioOutput.setSampleBufferDelegate(sink, queue: audioQueue) }
        // Sound the writer refused: the clip records without it and the microphone is reported as unavailable, as when it cannot attach.
        if let soundRefusal { events.yield(.microphoneUnavailable(soundRefusal)) }
    }

    /// Ends the clip for `end`; the first end stands. Returns whether a result will follow: a clip was recording, or ended with
    /// its result still to come.
    func end(_ end: WriterEnd) -> Bool {
        let isInFlight = writerQueue.sync { sink.end(end) }
        return isInFlight || shared.finishing.withLock { $0 > 0 }
    }

    func storage(freeBytes: Int64?) {
        writerQueue.sync { sink.storage(freeBytes: freeBytes) }
    }

    /// True from `start` until the clip's report is collected: configuring and starting another clip wait for it.
    var isClipInFlight: Bool {
        writerQueue.sync { sink.isInFlight }
    }

    /// True once the clip has ended and its file is being finished.
    var isFinishing: Bool {
        writerQueue.sync { sink.isFinishing }
    }

    /// True while the result of a collected clip is still being made.
    var hasResultPending: Bool {
        shared.finishing.withLock { $0 > 0 }
    }

    /// After the sink reported the clip finished (or the wait for it timed out): detaches the delegates, reads the report and
    /// yields the clip's result once its file is read back. Does nothing when no ended clip is waiting, so a second call, or a
    /// finish reported late for an earlier clip, changes nothing.
    func collect(timedOut: Bool = false) {
        guard let recording = pending else { return }
        guard let report = writerQueue.sync(execute: { sink.takeReport(timedOut: timedOut) }) else { return }
        pending = nil
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        shared.finishing.withLock { $0 += 1 }
        let results = results, shared = shared
        if report.end == .timedOut {
            // The writer never said it finished, so the file may still be written to: it is neither read nor reported as a clip.
            // The sink keeps the writer alive until its completion handler has run.
            let outcome = RecordingOutcome(writerEnd: .timedOut, hasFrames: report.hasFrames, isReadable: false)
            results.yield(RecordingResult(url: recording.url, option: recording.option, outcome: outcome, sidecar: nil))
            shared.finishing.withLock { $0 -= 1 }
            return
        }
        Task {
            let result = await ClipFinisher.finish(recording, recorder: .writer, drops: report.facts, errorMessage: report.errorText) { isReadable in
                RecordingOutcome(writerEnd: report.end, hasFrames: report.hasFrames, isReadable: isReadable)
            }
            results.yield(result)
            shared.finishing.withLock { $0 -= 1 }
        }
    }

    /// One level per channel of the audio output's connection; empty without a microphone or while detached.
    func audioLevels() -> [Double] {
        guard let connection = audioOutput.connection(with: .audio), connection.isActive else { return [] }
        return connection.audioChannels.map { AudioMeter.level(decibels: $0.averagePowerLevel) }
    }
}
