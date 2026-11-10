import AVFoundation
import Foundation
import Observation
import os

@MainActor @Observable
final class ProbeModel {
    var lines: [String] = []
    var isRunning = false
    var reportURL: URL?

    private var report = Report()
    private let logger = Logger(subsystem: "local.duocam.probe", category: "probe")

    func append(_ message: String) {
        lines.append(message)
        logger.info("\(message, privacy: .public)")
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        lines = []
        reportURL = nil
        defer { isRunning = false }

        let log: Log = { message in Task { @MainActor in self.append(message) } }
        report = Report()

        append("Requesting camera and microphone access")
        _ = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVAudioApplication.requestRecordPermission()

        append("Device")
        report.device = Inventory.device()
        save(report)

        append("Cameras, formats and outputs")
        report.cameras = await Task.detached { Inventory.cameras(log: log) }.value
        if report.cameras.isEmpty { log("No cameras were found") }
        save(report)

        append("Encoders")
        do {
            report.encoders = try await Task.detached { try Inventory.encoders() }.value
        } catch {
            report.errors.append(errorMessage(error, site: "ProbeModel:run"))
        }
        save(report)

        append("Audio")
        report.audio = await Task.detached { Inventory.audio() }.value
        save(report)

        append("RAW frame-rate test")
        let cameras = report.cameras
        if cameras.isEmpty {
            report.rawTest.errors.append("[ProbeModel:run] no cameras found, RAW test skipped")
        } else {
            report.rawTest = await RawTest.run(cameras: cameras, log: log) { info in
                Task { @MainActor in
                    self.report.rawTest = info
                    self.save(self.report)
                }
            }
        }

        report.finishedAt = Date()
        report.summary = summarize(report)
        reportURL = save(report)
        append("Done. Report: duocam-probe-report.json")
        if let data = try? encoder.encode(report) {
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") { logger.info("\(line, privacy: .public)") }
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    @discardableResult
    private func save(_ report: Report) -> URL? {
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = documents.appendingPathComponent("duocam-probe-report.json")
            try encoder.encode(report).write(to: url, options: .atomic)
            return url
        } catch {
            append(errorMessage(error, site: "ProbeModel:save"))
            return nil
        }
    }

    private func summarize(_ report: Report) -> Summary {
        var summary = Summary()
        summary.camerasFound = report.cameras.count
        let spaces = report.cameras.flatMap(\.formats).flatMap(\.colorSpaces)
        summary.appleLogSeen = spaces.contains("AppleLog")
        summary.appleLog2Seen = spaces.contains("AppleLog2")
        let movieCodecs = report.cameras.flatMap { $0.outputs.movieCodecTypes + $0.outputs.movieCodecTypesAcrossFormats }
        summary.proResInMovieOutputCodecs = movieCodecs.contains { $0.hasPrefix("ap") && !$0.hasPrefix("apr") }
        summary.proResRawInMovieOutputCodecs = movieCodecs.contains { $0 == "aprn" || $0 == "aprh" }
        summary.bayerOnVideoDataOutput = report.cameras.contains { !$0.outputs.bayerVideoFormats.isEmpty }
        let controls = report.cameras.compactMap(\.outputs.supportsControls)
        summary.cameraControlSupported = controls.isEmpty ? nil : controls.contains(true)
        if let run = report.rawTest.sustainedRun, run.framesDelivered > 0 {
            summary.fastestSustainedRawFps = run.fps
            summary.fastestSustainedRawMethod = run.method
            if let w = run.rawWidth, let h = run.rawHeight { summary.fastestSustainedRawSize = "\(w)x\(h)" }
        }
        if report.cameras.isEmpty { summary.notes.append("No cameras were found.") }
        return summary
    }
}
