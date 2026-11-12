import AVFoundation

/// Report section B: one writer trial. A session with only the back wide camera and one data output feeds a `.mov` writer
/// for a few seconds; the camera's frames are counted, timed and dropped when the writer is not ready.
nonisolated enum RecorderCheckTrial {
    static let recordDuration = Duration.seconds(6)
    private static let firstFrameDeadline = Duration.seconds(5)

    @concurrent static func run(target: RecorderCheckTarget, codec: RecorderCheckCodec, directory: URL) async -> RecorderCheckTrialResult {
        var result = RecorderCheckTrialResult(target: target.label, requestedWidth: Int(target.width), requestedHeight: Int(target.height),
                                              requestedFramesPerSecond: target.framesPerSecond, codec: codec.label, codecType: codec.type.rawValue)
        result.thermalBefore = RecorderCheckSnapshot.thermal
        await execute(&result, target: target, codec: codec, directory: directory)
        result.thermalAfter = RecorderCheckSnapshot.thermal
        return result
    }

    private static func execute(_ result: inout RecorderCheckTrialResult, target: RecorderCheckTarget, codec: RecorderCheckCodec, directory: URL) async {
        let context = "target: \(target.label), codec: \(codec.type.rawValue)"
        guard let device = RecorderCheckRig.backWideCamera() else {
            result.skipReason = RecorderCheck.logError("execute", "No back wide camera", context: context)
            return
        }
        guard let chosen = RecorderCheckFormats.pick(on: device, for: target) else {
            result.skipReason = RecorderCheck.logError("execute", "No camera format at this size and rate", context: context)
            return
        }
        result.format = chosen.pick
        let rig: RecorderCheckRig
        do {
            rig = try RecorderCheckRig(device: device, preset: .inputPriority)
            rig.requestFullSizeBuffers()
            try rig.apply(format: chosen.format, target: target)
        } catch {
            result.skipReason = RecorderCheck.logError("execute", "The session could not be set up", context: "\(context), reason: \(RecorderCheck.describe(error))")
            return
        }
        result.activeColorSpace = RecorderCheckFormats.colorSpaceName(device.activeColorSpace)

        // The 10-bit format when the output offers one. The list is read after the format is set: it depends on the configuration.
        let offered = rig.output.availableVideoPixelFormatTypes
        result.offeredPixelFormats = offered.map(RecorderCheckFourCC.string)
        let tenBit = [kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange].first { offered.contains($0) }
        if let tenBit {
            rig.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: tenBit]
            result.pixelFormatRequested = RecorderCheckFourCC.string(tenBit)
        } else {
            result.pixelFormatRequested = "none (output default)"
        }

        let writerSettings = Self.writerSettings(for: codec, target: target, output: rig.output)
        result.writerSettingsSource = writerSettings.source
        result.writerSettings = RecorderCheckDescribe.value(writerSettings.settings)
        result.colourPropertiesInWriterSettings = writerSettings.settings[AVVideoColorPropertiesKey].map { RecorderCheckDescribe.value($0) }

        let url = directory.appending(path: "trial-\(target.label)-\(codec.type.rawValue).mov")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sink: RecorderCheckSink
        do {
            sink = try RecorderCheckSink(url: url, settings: writerSettings.settings)
            result.writerAcceptedSettings = true
            result.writerInputExpectsRealTime = sink.isRealTimeConfirmed
        } catch let failure as RecorderCheckFailure {
            result.writerAcceptedSettings = !failure.isSettingsRejection
            result.writerSetupError = RecorderCheck.logError("execute", "The writer could not be set up", context: "\(context), reason: \(failure.message)")
            result.skipReason = result.writerSetupError
            return
        } catch {
            result.writerSetupError = RecorderCheck.logError("execute", "The writer could not be set up", context: "\(context), reason: \(error.localizedDescription)")
            result.skipReason = result.writerSetupError
            return
        }

        // The sink's state belongs to this queue: every call into it from here goes through `queue.sync`.
        let queue = DispatchSerialQueue(label: "opencam.recorder-check.frames", qos: .userInitiated)
        rig.output.setSampleBufferDelegate(sink, queue: queue)
        rig.session.startRunning()
        if !rig.session.isRunning {
            result.failure = RecorderCheck.logError("execute", "The session did not start", context: context)
        } else if await Self.waitForFirstFrame(of: sink, on: queue) {
            // The recording time counts from the first frame, so a slow start does not shorten it.
            try? await Task.sleep(for: recordDuration)
        } else {
            result.failure = RecorderCheck.logError("execute", "No frame arrived", context: "\(context), waited: \(firstFrameDeadline)")
        }
        queue.sync { sink.stop() }
        rig.output.setSampleBufferDelegate(nil, queue: nil)
        rig.session.stopRunning()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.sync { sink.beginFinishing { continuation.resume() } }
        }

        let counts = queue.sync { sink.result() }
        result.counts = counts
        let file = await RecorderCheckReadback.read(url)
        result.file = file
        if let bytes = file.fileBytes {
            if let seconds = file.durationSeconds, seconds > 0 {
                result.dataRateMegabitsPerSecond = Double(bytes) * 8 / seconds / 1_000_000
                result.dataRateBasis = "file size over the file's duration"
            } else if let first = counts.firstAppendedPTS, let last = counts.lastAppendedPTS, last > first {
                let span = last - first + 1 / Double(target.framesPerSecond)
                result.dataRateMegabitsPerSecond = Double(bytes) * 8 / span / 1_000_000
                result.dataRateBasis = "file size over the appended presentation-time span plus one frame"
            }
        }
    }

    /// The output's recommended settings for the codec when its writer list has the codec (asking otherwise raises an exception,
    /// AVCaptureVideoDataOutput.h); else codec, width and height built here from the camera format.
    private static func writerSettings(for codec: RecorderCheckCodec, target: RecorderCheckTarget, output: AVCaptureVideoDataOutput)
        -> (settings: [String: Any], source: String) {
        if output.availableVideoCodecTypesForAssetWriter(writingTo: .mov).contains(codec.type),
           let recommended = output.recommendedVideoSettings(forVideoCodecType: codec.type, assetWriterOutputFileType: .mov) {
            return (recommended, "recommended")
        }
        let built: [String: Any] = [AVVideoCodecKey: codec.type.rawValue, AVVideoWidthKey: Int(target.width), AVVideoHeightKey: Int(target.height)]
        return (built, "constructed (codec not in the output's asset-writer list for .mov)")
    }

    private static func waitForFirstFrame(of sink: RecorderCheckSink, on queue: DispatchSerialQueue) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + firstFrameDeadline
        while clock.now < deadline {
            if queue.sync(execute: { sink.deliveredCount }) > 0 { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return queue.sync { sink.deliveredCount } > 0
    }
}
