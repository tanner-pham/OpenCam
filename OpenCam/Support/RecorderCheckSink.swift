import AVFoundation
import CoreMedia
import CoreVideo

/// Takes the data output's frames on its serial queue and offers each one to an asset writer input that expects real-time
/// media, counting what happens. The frame is appended only when the input says it is ready (`isReadyForMoreMediaData`); a
/// frame that arrives while it is not ready is dropped and counted. The only call timed is `append`.
///
/// All state is confined to the serial queue the output delivers on: the object is not `Sendable`, and everything outside the
/// delegate callbacks (`stop`, `beginFinishing`, `result`, `deliveredCount`) is called through `queue.sync` by the trial. A
/// finished, immutable `RecorderCheckSinkResult` is handed back.
///
/// iOS 27 deprecates `add`, `append`, `isReadyForMoreMediaData` and `expectsMediaDataInRealTime` in favour of
/// `inputReceiver(for:)` and `SampleBufferReceiver.appendImmediately`, which takes a `CMReadySampleBuffer`. That type's only initializer from the
/// delegate's `CMSampleBuffer` (`init(unsafeBuffer:)`) wants a `sending` buffer, and the delegate's parameter is not one, so it
/// cannot be made here without `@unchecked Sendable` or `nonisolated(unsafe)`. The check uses one consistent legacy
/// path (add, append, readiness) that has long been proven; it sits in two methods marked deprecated so the build stays free of warnings.
nonisolated final class RecorderCheckSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, RecorderCheckWriterOpening {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    /// What `expectsMediaDataInRealTime` read back after it was set.
    private(set) var isRealTimeConfirmed = false

    private var isStopped = false
    private var hasFailed = false
    private var counts = RecorderCheckSinkResult()
    private var firstDelivered: CMTime?
    private var lastDelivered: CMTime?
    private var firstAppended: CMTime?
    private var lastAppended: CMTime?
    private var appendTotal = Duration.zero
    private var appendWorst = Duration.zero
    private var appendCalls = 0

    /// Opens the writer the long-proven way: `canApply`, `canAdd`, `add`, `expectsMediaDataInRealTime`, then started. Those
    /// calls are deprecated in iOS 27, so they sit in a method marked deprecated that the trial reaches through
    /// `RecorderCheckWriterOpening`, which keeps the build free of warnings.
    @available(iOS, deprecated: 27.0, message: "Uses the legacy writer path on purpose; see the type's comment")
    func open(url: URL, settings: [String: Any]) throws {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw RecorderCheckFailure(message: "The writer could not be made: \(error.localizedDescription)")
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw RecorderCheckFailure(message: "The writer refused the output settings (canApply was false)", isSettingsRejection: true)
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        isRealTimeConfirmed = input.expectsMediaDataInRealTime
        guard writer.canAdd(input) else { throw RecorderCheckFailure(message: "The writer cannot take the video input") }
        writer.add(input)
        do {
            try writer.start()
        } catch {
            throw RecorderCheckFailure(message: "start failed: \(Self.statusName(writer.status)), \(error.localizedDescription)")
        }
        self.writer = writer
        self.input = input
    }

    /// Call on the output's queue.
    var deliveredCount: Int { counts.framesDelivered }

    @available(iOS, deprecated: 27.0, message: "Measures the deprecated append on purpose; see the type's comment")
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isStopped, let writer, let input else { return }
        counts.framesDelivered += 1
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstDelivered == nil {
            firstDelivered = presentationTime
            counts.firstFrame = Self.facts(of: sampleBuffer)
            writer.startSession(atSourceTime: presentationTime)
        }
        lastDelivered = presentationTime
        guard !hasFailed else {
            counts.framesNotAppendedAfterWriterFailure += 1
            return
        }
        guard input.isReadyForMoreMediaData else {
            counts.framesNotAppendedInputNotReady += 1
            return
        }
        let started = ContinuousClock.now
        let isAppended = input.append(sampleBuffer)
        let elapsed = ContinuousClock.now - started
        appendTotal += elapsed
        appendWorst = max(appendWorst, elapsed)
        appendCalls += 1
        if isAppended {
            counts.framesAppended += 1
            firstAppended = firstAppended ?? presentationTime
            lastAppended = presentationTime
        } else {
            hasFailed = true
            let reason = writer.error?.localizedDescription ?? "no error"
            counts.appendError = "append returned false: \(reason) (writer status \(Self.statusName(writer.status)))"
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isStopped else { return }
        counts.framesDroppedByOutput += 1
        counts.dropReasons[Self.dropReason(of: sampleBuffer), default: 0] += 1
    }

    /// No more frames are counted or appended; the input is told no more will come. Call on the output's queue.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        input?.markAsFinished()
    }

    /// Starts ending the file and calls `completion` when it is done. With no frame ever delivered there is no writing session to
    /// end, so the writer is cancelled. Call on the output's queue.
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

    /// The finished counts, once `stop()` and the finishing are done. Call on the output's queue.
    func result() -> RecorderCheckSinkResult {
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
        counts.writerStatus = writer.map { Self.statusName($0.status) } ?? "not opened"
        counts.writerError = writer?.error.map { "\($0.localizedDescription) [\(String(describing: $0))]" }
        return counts
    }

    private static func rate(frames: Int, from first: CMTime?, to last: CMTime?) -> Double? {
        guard frames > 1, let first, let last else { return nil }
        let span = (last - first).seconds
        return span > 0 ? Double(frames - 1) / span : nil
    }

    static func statusName(_ status: AVAssetWriter.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .writing: "writing"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    /// The drop-reason attachment (CMSampleBuffer.h, `kCMSampleBufferAttachmentKey_DroppedFrameReason`) with the extra
    /// info attachment when there is one.
    static func dropReason(of sampleBuffer: CMSampleBuffer) -> String {
        guard let reason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil) else {
            return "none given"
        }
        let text = String(describing: reason)
        guard let info = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReasonInfo, attachmentModeOut: nil) else {
            return text
        }
        return "\(text) / \(String(describing: info))"
    }

    static func facts(of sampleBuffer: CMSampleBuffer) -> RecorderCheckFrameFacts {
        var facts = RecorderCheckFrameFacts()
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            facts.note = "The first sample buffer has no image buffer"
            return facts
        }
        facts.width = CVPixelBufferGetWidth(buffer)
        facts.height = CVPixelBufferGetHeight(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        facts.pixelFormat = RecorderCheckFourCC.string(format)
        facts.bitDepthFromPixelFormat = RecorderCheckFormats.bitDepth(ofSubType: format)
        facts.colourPrimaries = Self.attachment(kCVImageBufferColorPrimariesKey, of: buffer)
        facts.transferFunction = Self.attachment(kCVImageBufferTransferFunctionKey, of: buffer)
        facts.yCbCrMatrix = Self.attachment(kCVImageBufferYCbCrMatrixKey, of: buffer)
        return facts
    }

    private static func attachment(_ key: CFString, of buffer: CVBuffer) -> String? {
        CVBufferCopyAttachment(buffer, key, nil).map { String(describing: $0) }
    }
}

/// The sink's state is confined to the output's serial queue; it is never shared across tasks.
@available(*, unavailable)
extension RecorderCheckSink: Sendable {}
