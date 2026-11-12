import AVFoundation
import OSLog
import UIKit

/// A second one-off diagnostic, reached only with the `-recorderCheck2` launch argument. The first check ran with the screen
/// face down or in the dark, so the encoders had little to encode. This one shows the live preview, records sound, runs each trial
/// for 30 seconds, and can put each frame through the app's colour table before it is written. It asks you to point the phone
/// at a busy, moving scene. The report goes to `Documents/recorder-check-2.json`; every movie file is deleted.
enum RecorderCheck2 {
    private nonisolated static let logger = Logger(subsystem: "local.opencam.app", category: "RecorderCheck2")
    static let fileName = "recorder-check-2.json"
    private static let pauseBetweenTrials = Duration.seconds(5)
    private static let minimumFreeBytes: Int64 = 8_000_000_000

    /// Logs an error in the house format and returns the same text for the report.
    @discardableResult
    nonisolated static func logError(_ function: String, _ description: String, context: String) -> String {
        let text = "[RecorderCheck2:\(function)] \(description) — {\(context)}"
        logger.error("\(text, privacy: .public)")
        return text
    }

    static func runAndWrite(progress: RecorderCheck2Progress) async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            progress.isFinished = true
        }
        var report = RecorderCheck2Report(takenAt: .now, buildConfiguration: buildConfiguration, notes: notes, device: .read())
        report.stateAtStart = RecorderCheckSnapshot.now()
        let scratch = FileManager.default.temporaryDirectory.appending(path: "recorder-check-2", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: scratch)
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            report.errors.append(logError("runAndWrite", "The scratch folder could not be made", context: "reason: \(error.localizedDescription)"))
            finish(&report)
            return
        }
        save(report)
        guard await hasCameraAccess() else {
            report.errors.append(logError("runAndWrite", "No camera access", context: "status: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)"))
            finish(&report)
            return
        }

        let plans = RecorderCheck2Plan.all
        var stopReason: String?
        for (index, plan) in plans.enumerated() {
            if stopReason == nil {
                if RecorderCheckSnapshot.isHot {
                    stopReason = "Thermal state reached \(RecorderCheckSnapshot.thermal) before the trial \(plan.label)"
                } else if FreeSpace.availableBytes() < minimumFreeBytes {
                    stopReason = "Free disk space fell under 8 GB before the trial \(plan.label)"
                }
                report.trialsStoppedEarly = stopReason
            }
            if let stopReason {
                report.trials.append(skipped(plan, reason: "Not run: \(stopReason)"))
                continue
            }
            progress.line = "Trial \(index + 1) of \(plans.count): \(plan.label)"
            let result = await RecorderCheck2Trial.run(plan, progress: progress, directory: scratch)
            report.trials.append(result)
            if let reason = result.skipReason ?? result.failure { report.errors.append(reason) }
            save(report)
            if index < plans.count - 1 {
                progress.line = "Resting before trial \(index + 2) of \(plans.count)"
                try? await Task.sleep(for: pauseBetweenTrials)
            }
        }
        finish(&report)
    }

    private static func skipped(_ plan: RecorderCheck2Plan, reason: String) -> RecorderCheck2TrialResult {
        var result = RecorderCheck2TrialResult(label: plan.label, requestedWidth: Int(plan.target.width), requestedHeight: Int(plan.target.height),
                                               requestedFramesPerSecond: plan.target.framesPerSecond, codec: plan.codec.label,
                                               codecType: plan.codec.type.rawValue, usesColourTable: plan.usesColourPass)
        result.skipReason = reason
        return result
    }

    private static func hasCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private static func finish(_ report: inout RecorderCheck2Report) {
        report.stateAtEnd = RecorderCheckSnapshot.now()
        report.device.freeDiskBytesAtEnd = FreeSpace.availableBytes()
        let skipped = report.trials.filter { $0.skipReason != nil }.count
        let failed = report.trials.filter { $0.skipReason == nil && ($0.failure != nil || $0.video?.writerStatus != "completed" || $0.video?.appendError != nil) }.count
        let ran = report.trials.count - skipped
        report.notes.append("Summary: \(report.trials.count) trials planned, \(ran) ran, \(skipped) skipped, \(failed) failed (of those that ran).")
        report.isComplete = true
        save(report)
    }

    /// A report that could not be written is logged; the run goes on.
    private static func save(_ report: RecorderCheck2Report) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try encoder.encode(report).write(to: directory.appending(path: fileName), options: .atomic)
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
        "Each trial records for 30 seconds from its first frame with the live preview on screen, sound from the default microphone (when microphone access was already granted; it is never asked for), the 10-bit x420 data output and HLG BT.2020 when the format supports it.",
        "Trials 4 to 6 pass every frame through the app's colour table (a 33-point table with a mild contrast curve, LookRenderer.applyCube) into a new 10-bit pixel buffer before it is written. This stands in for baking a look or a Log-style curve into the recording.",
        "The trials still do not include: a recording of minutes, a second look pass, stabilisation, camera controls changing during recording, or the app's own viewfinder look drawing.",
        "meanLumaFirstFrame and meanLumaLastFrame are the mean luma of a sparse sample of the Y plane, 0 to 1. Below about 0.1 the camera was looking at darkness and the encoders had little to encode.",
        "The phone's state changes the result: charging, heat (thermalBefore and thermalAfter per trial), battery level, low power mode and free disk space are recorded per trial. Trials run back to back with a 5 second rest, so heat builds up from one trial to the next.",
        "A frame is offered to the writer only when the input says it is ready; otherwise it is dropped and counted (framesNotAppendedInputNotReady). In the colour table trials a frame is not rendered at all when the capture is already more than one frame behind real time (framesDroppedRenderBusy).",
        "Frames and sound are delivered on separate queues and all writer work runs on one serial writer queue, so the sound waits behind a video append; that wait is part of what a one-writer recorder pays.",
        "The effective frame rates are the frames after the first divided by the time between the first and last presentation timestamps.",
        "The build configuration is recorded in buildConfiguration. A Debug build is slower than a Release build; trust the writer and render numbers of a Release run more.",
    ]
}
