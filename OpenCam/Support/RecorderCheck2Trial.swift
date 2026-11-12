import AVFoundation

/// One trial of the second check. Runs on the main actor because the session is shared with the preview layer, which lives
/// there; `startRunning` and `stopRunning` block it for a moment, and nothing else on screen needs it meanwhile. The frames and
/// the sound are handled on their own queues.
enum RecorderCheck2Trial {
    static let recordDuration = Duration.seconds(30)
    private static let earlyPreviewCheck = Duration.seconds(3)
    private static let firstFrameDeadline = Duration.seconds(5)

    static func run(_ plan: RecorderCheck2Plan, progress: RecorderCheck2Progress, directory: URL) async -> RecorderCheck2TrialResult {
        let target = plan.target
        var result = RecorderCheck2TrialResult(label: plan.label, requestedWidth: Int(target.width), requestedHeight: Int(target.height),
                                               requestedFramesPerSecond: target.framesPerSecond, codec: plan.codec.label,
                                               codecType: plan.codec.type.rawValue, usesColourTable: plan.usesColourPass)
        let before = RecorderCheckSnapshot.now()
        result.thermalBefore = before.thermalState
        result.batteryPercentBefore = before.batteryLevelPercent
        result.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        result.freeDiskBytesBefore = FreeSpace.availableBytes()
        await execute(&result, plan: plan, progress: progress, directory: directory)
        progress.show(nil)
        let after = RecorderCheckSnapshot.now()
        result.thermalAfter = after.thermalState
        result.batteryPercentAfter = after.batteryLevelPercent
        return result
    }

    private static func execute(_ result: inout RecorderCheck2TrialResult, plan: RecorderCheck2Plan, progress: RecorderCheck2Progress, directory: URL) async {
        let target = plan.target
        let context = "trial: \(plan.label)"
        guard let device = RecorderCheckRig.backWideCamera() else {
            result.skipReason = RecorderCheck2.logError("execute", "No back wide camera", context: context)
            return
        }
        guard let chosen = RecorderCheckFormats.pick(on: device, for: target) else {
            result.skipReason = RecorderCheck2.logError("execute", "No camera format at this size and rate", context: context)
            return
        }
        result.format = chosen.pick
        let rig: RecorderCheckRig
        do {
            rig = try RecorderCheckRig(device: device, preset: .inputPriority)
        } catch {
            result.skipReason = RecorderCheck2.logError("execute", "The session could not be set up", context: "\(context), reason: \(RecorderCheck.describe(error))")
            return
        }
        let audioOutput = addSound(to: rig.session, audio: &result.audio, context: context)
        rig.requestFullSizeBuffers()
        do {
            try rig.apply(format: chosen.format, target: target)
        } catch {
            result.skipReason = RecorderCheck2.logError("execute", "The camera format could not be applied", context: "\(context), reason: \(RecorderCheck.describe(error))")
            return
        }
        result.activeColorSpace = RecorderCheckFormats.colorSpaceName(device.activeColorSpace)

        let offered = rig.output.availableVideoPixelFormatTypes
        result.offeredPixelFormats = offered.map(RecorderCheckFourCC.string)
        let tenBit = [kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange].first { offered.contains($0) }
        if let tenBit {
            rig.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: tenBit]
            result.pixelFormatRequested = RecorderCheckFourCC.string(tenBit)
        } else {
            result.pixelFormatRequested = "none (output default)"
        }

        let videoSettings = writerSettings(for: plan.codec, target: target, output: rig.output)
        result.writerSettingsSource = videoSettings.source
        result.writerSettings = RecorderCheckDescribe.value(videoSettings.settings)
        var audioSettings: [String: Any]?
        if let audioOutput {
            let settings = audioWriterSettings(from: audioOutput)
            result.audio.settingsSource = settings.source
            result.audio.settings = RecorderCheckDescribe.value(settings.settings)
            audioSettings = settings.settings
        }

        let url = directory.appending(path: "trial2-\(plan.target.label)-\(plan.codec.type.rawValue)-\(plan.usesColourPass ? "table" : "plain").mov")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let videoQueue = DispatchSerialQueue(label: "opencam.recorder-check-2.video", qos: .userInitiated)
        let audioQueue = DispatchSerialQueue(label: "opencam.recorder-check-2.audio", qos: .userInitiated)
        let writerQueue = DispatchSerialQueue(label: "opencam.recorder-check-2.writer", qos: .userInitiated)
        let stage = RecorderCheck2VideoStage(usesColourPass: plan.usesColourPass, framesPerSecond: target.framesPerSecond)
        let sink = RecorderCheck2Sink(writerQueue: writerQueue, stage: stage)
        do {
            let adaptorFormat = plan.usesColourPass ? tenBit.map { (width: Int(target.width), height: Int(target.height), pixelFormat: $0) } : nil
            if plan.usesColourPass, adaptorFormat == nil {
                result.skipReason = RecorderCheck2.logError("execute", "The colour table pass needs a 10-bit pixel format and the output offers none", context: context)
                return
            }
            let opening: any RecorderCheck2WriterOpening = sink
            let audioNote = try writerQueue.sync { try opening.open(url: url, videoSettings: videoSettings.settings, audioSettings: audioSettings, adaptorFormat: adaptorFormat) }
            result.writerAcceptedSettings = true
            if let audioNote {
                result.audio.status = RecorderCheck2.logError("execute", "The sound could not be added to the writer", context: "\(context), reason: \(audioNote)")
            }
        } catch let failure as RecorderCheckFailure {
            result.writerAcceptedSettings = !failure.isSettingsRejection
            result.writerSetupError = RecorderCheck2.logError("execute", "The writer could not be set up", context: "\(context), reason: \(failure.message)")
            result.skipReason = result.writerSetupError
            return
        } catch {
            result.writerSetupError = RecorderCheck2.logError("execute", "The writer could not be set up", context: "\(context), reason: \(error.localizedDescription)")
            result.skipReason = result.writerSetupError
            return
        }
        result.writerInputExpectsRealTime = writerQueue.sync { sink.isVideoRealTimeConfirmed }

        rig.output.setSampleBufferDelegate(sink, queue: videoQueue)
        audioOutput?.setSampleBufferDelegate(sink, queue: audioQueue)
        progress.show(rig.session)
        rig.session.startRunning()
        if !rig.session.isRunning {
            result.failure = RecorderCheck2.logError("execute", "The session did not start", context: context)
        } else if await waitForFirstFrame(of: sink, on: writerQueue) {
            try? await Task.sleep(for: earlyPreviewCheck)
            result.wasPreviewingEarly = progress.isPreviewing
            try? await Task.sleep(for: recordDuration - earlyPreviewCheck)
            result.wasPreviewingAtEnd = progress.isPreviewing
        } else {
            result.failure = RecorderCheck2.logError("execute", "No frame arrived", context: "\(context), waited: \(firstFrameDeadline)")
        }
        writerQueue.sync { sink.stop() }
        rig.output.setSampleBufferDelegate(nil, queue: nil)
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        rig.session.stopRunning()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerQueue.sync { sink.beginFinishing { continuation.resume() } }
        }

        let finished = writerQueue.sync { sink.results() }
        result.video = finished.video
        let audioStatus = result.audio.status
        var audioFacts = finished.audio
        audioFacts.status = audioStatus == "recorded" || audioStatus == "not tried" ? "recorded" : audioStatus
        audioFacts.settingsSource = result.audio.settingsSource
        audioFacts.settings = result.audio.settings
        result.audio = audioFacts
        if audioSettings == nil, audioStatus == "not tried" { result.audio.status = "no sound input" }
        videoQueue.sync {
            result.meanLumaFirstFrame = stage.meanLumaFirstFrame
            result.meanLumaLastFrame = stage.meanLumaLastFrame
            if plan.usesColourPass { result.render = stage.renderStats() }
        }

        let file = await RecorderCheckReadback.read(url)
        result.file = file
        result.freeDiskBytesAfter = FreeSpace.availableBytes()
        if let bytes = file.fileBytes {
            if let seconds = file.durationSeconds, seconds > 0 {
                result.dataRateMegabitsPerSecond = Double(bytes) * 8 / seconds / 1_000_000
                result.dataRateBasis = "file size over the file's duration"
            }
        }
        try? FileManager.default.removeItem(at: url)
        result.freeDiskBytesAfterDelete = FreeSpace.availableBytes()
    }

    /// The default microphone, only when access is already granted; the permission is never asked for here. Sets the status.
    private static func addSound(to session: AVCaptureSession, audio: inout RecorderCheck2AudioFacts, context: String) -> AVCaptureAudioDataOutput? {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            audio.status = "not authorized"
            return nil
        }
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            audio.status = RecorderCheck2.logError("addSound", "No microphone", context: context)
            return nil
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: microphone)
        } catch {
            audio.status = RecorderCheck2.logError("addSound", "The microphone input could not be made", context: "\(context), reason: \(error.localizedDescription)")
            return nil
        }
        let output = AVCaptureAudioDataOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            audio.status = RecorderCheck2.logError("addSound", "The session cannot take the microphone", context: context)
            return nil
        }
        session.addInput(input)
        session.addOutput(output)
        audio.status = "recorded"
        return output
    }

    /// 48 kHz stereo AAC from the output's recommended settings for .mov when it has them, else built here.
    private static func audioWriterSettings(from output: AVCaptureAudioDataOutput) -> (settings: [String: Any], source: String) {
        if let recommended = output.recommendedAudioSettingsForAssetWriter(writingTo: .mov) {
            return (recommended, "recommended")
        }
        let built: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000]
        return (built, "hand-built AAC (the output gave no recommended settings)")
    }

    /// The output's recommended settings for the codec when its writer list has the codec (asking otherwise raises an exception,
    /// AVCaptureVideoDataOutput.h); else codec, width and height built from the camera format.
    private static func writerSettings(for codec: RecorderCheckCodec, target: RecorderCheckTarget, output: AVCaptureVideoDataOutput) -> (settings: [String: Any], source: String) {
        if output.availableVideoCodecTypesForAssetWriter(writingTo: .mov).contains(codec.type),
           let recommended = output.recommendedVideoSettings(forVideoCodecType: codec.type, assetWriterOutputFileType: .mov) {
            return (recommended, "recommended")
        }
        let built: [String: Any] = [AVVideoCodecKey: codec.type.rawValue, AVVideoWidthKey: Int(target.width), AVVideoHeightKey: Int(target.height)]
        return (built, "constructed (codec not in the output's asset-writer list for .mov)")
    }

    private static func waitForFirstFrame(of sink: RecorderCheck2Sink, on queue: DispatchSerialQueue) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + firstFrameDeadline
        while clock.now < deadline {
            if queue.sync(execute: { sink.deliveredCount }) > 0 { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return queue.sync { sink.deliveredCount } > 0
    }
}
