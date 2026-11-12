import AVFoundation
import OSLog

/// A one-off diagnostic, reached only with the `-recorderCheck` launch argument. It asks the phone, with the camera to itself,
/// what a custom video recorder could do: what the video data output offers (A), whether an asset writer can encode HEVC and
/// ProRes from the camera's frames in real time (B), and how fast RAW photos can be taken in a row (C). The report goes to
/// `Documents/recorder-check.json`; every movie and photo file it makes is deleted.
nonisolated enum RecorderCheck {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "RecorderCheck")
    private static let pauseBetweenTrials = Duration.seconds(2)

    /// Logs an error in the house format and returns the same text for the report.
    @discardableResult
    static func logError(_ function: String, _ description: String, context: String) -> String {
        let text = "[RecorderCheck:\(function)] \(description) — {\(context)}"
        logger.error("\(text, privacy: .public)")
        return text
    }

    static func describe(_ error: any Error) -> String {
        (error as? RecorderCheckFailure)?.message ?? error.localizedDescription
    }

    /// Runs off the main actor: starting a session blocks.
    @concurrent static func runAndWrite() async {
        var report = RecorderCheckReport(takenAt: .now, buildConfiguration: Self.buildConfiguration, notes: Self.notes, device: .read())
        report.stateAtStart = await RecorderCheckSnapshot.now()
        do {
            try RecorderCheckStore.resetScratch()
        } catch {
            report.errors.append(logError("runAndWrite", "The scratch folder could not be made", context: "reason: \(error.localizedDescription)"))
            await finish(&report)
            return
        }
        save(report)
        guard await hasCameraAccess() else {
            report.errors.append(logError("runAndWrite", "No camera access", context: "status: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)"))
            await finish(&report)
            return
        }

        let sectionA = await RecorderCheckOffers.collect()
        report.dataOutputOffers = sectionA.offers
        report.photoPresetOffer = sectionA.preset
        report.completedSections.append("A: what the data output offers")
        save(report)

        await runTrials(&report)
        report.completedSections.append("B: writer trials")
        save(report)

        report.rawCadence = await RecorderCheckPhotoCadence.run(directory: RecorderCheckStore.scratchDirectory)
        report.completedSections.append("C: RAW photo cadence")
        await finish(&report)
    }

    /// Every size and rate with every codec. A thermal state of serious or worse stops the trials that have not started; they
    /// stay in the report as skipped, with the reason.
    private static func runTrials(_ report: inout RecorderCheckReport) async {
        var stopReason: String?
        for target in RecorderCheckTarget.all {
            for codec in RecorderCheckCodec.allCases {
                if stopReason == nil, RecorderCheckSnapshot.isHot {
                    stopReason = "Thermal state reached \(RecorderCheckSnapshot.thermal) before the trial \(target.label) \(codec.label)"
                    report.writerTrialsStoppedEarly = stopReason
                }
                if let stopReason {
                    var skipped = RecorderCheckTrialResult(target: target.label, requestedWidth: Int(target.width), requestedHeight: Int(target.height),
                                                           requestedFramesPerSecond: target.framesPerSecond, codec: codec.label, codecType: codec.type.rawValue)
                    skipped.skipReason = "Not run: \(stopReason)"
                    report.writerTrials.append(skipped)
                    continue
                }
                let result = await RecorderCheckTrial.run(target: target, codec: codec, directory: RecorderCheckStore.scratchDirectory)
                report.writerTrials.append(result)
                if let reason = result.skipReason ?? result.failure { report.errors.append(reason) }
                save(report)
                try? await Task.sleep(for: pauseBetweenTrials)
            }
        }
    }

    private static func hasCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private static func finish(_ report: inout RecorderCheckReport) async {
        report.stateAtEnd = await RecorderCheckSnapshot.now()
        report.device.freeDiskBytesAtEnd = FreeSpace.availableBytes()
        report.isComplete = true
        save(report)
        RecorderCheckStore.removeScratch()
    }

    /// A report that could not be written is logged; the run goes on.
    private static func save(_ report: RecorderCheckReport) {
        do {
            try RecorderCheckStore.write(report)
        } catch {
            logError("save", "The report could not be written", context: "reason: \(error.localizedDescription)")
        }
    }

    private static var buildConfiguration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    private static let notes = [
        "The trials had no audio and no preview layer: the session held the back wide camera and one video data output, and nothing else.",
        "Nothing was shown on screen but one line of text, and the screen was kept on. A real recorder also draws a preview and records sound; it will be slower than these numbers.",
        "The phone's state changes the result: whether it was charging, how hot it was (thermalBefore and thermalAfter per trial, stateAtStart and stateAtEnd for the run) and how full its disk was. Trials run back to back with a 2 second pause, so heat builds up from one trial to the next.",
        "The writer input expects media data in real time. A frame is offered with appendImmediately; if the input says it is not ready the frame is dropped and counted (framesNotAppendedInputNotReady). That count is the measurement.",
        "The effective frame rates are the frames after the first divided by the time between the first and last presentation timestamps, so a stall or a dropped frame shows as a lower rate.",
        "Each writer trial records for 6 seconds from its first frame. It says nothing about recordings that last minutes or about heat building over minutes.",
        "The build configuration is recorded in buildConfiguration. A Debug build is slower than a Release build; trust the writer numbers of a Release run more.",
        "File sizes and data rates come from the finished file; the data rate is over the file's duration (see dataRateBasis).",
        "The 10-bit pixel format is asked of the output when it offers one; pixelFormatRequested and counts.firstFrame say what was asked and what arrived.",
        "bitDepthFromSubType and bitDepthFromPixelFormat are read from a table of the 10-bit formats this check knows, not measured from the pixels.",
    ]
}
