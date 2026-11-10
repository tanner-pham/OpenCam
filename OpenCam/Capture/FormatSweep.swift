import Foundation
import Observation
import OSLog

/// Records a short clip in each option, one at a time, compares each file with the request, and writes a report.
/// Every camera step goes through `driver`, so the model's configure queue and recording rules stay in charge.
/// A failing option is recorded and the sweep moves on; restoring the user's selection is the model's job.
@MainActor @Observable final class FormatSweep {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "FormatSweep")

    private(set) var done = 0
    let total: Int
    private(set) var rows: [SweepRow] = []
    private(set) var isRunning = false
    private(set) var reportURL: URL?
    /// Nil until the sweep ends; then "Done. 80 passed, 4 failed. Saved sweep-….json." or "Cancelled after 12 of 84. Saved sweep-….json."
    private(set) var resultText: String?

    @ObservationIgnored private weak var driver: (any SweepDriver)?
    @ObservationIgnored private let store: CaptureStore
    @ObservationIgnored private let lens: Lens
    @ObservationIgnored private let options: [VideoOption]
    @ObservationIgnored private let keepsClips: Bool
    @ObservationIgnored private let clipDuration: Duration
    @ObservationIgnored private var isCancelled = false
    @ObservationIgnored private var hasStarted = false
    /// A result that arrived before the sweep waited for it, such as a recording that failed to start.
    @ObservationIgnored private var arrivedResult: RecordingResult?
    @ObservationIgnored private var resultWaiter: CheckedContinuation<RecordingResult, Never>?

    init(driver: any SweepDriver, store: CaptureStore, lens: Lens, options: [VideoOption], keepsClips: Bool,
         clipDuration: Duration = .seconds(SweepRow.clipSeconds)) {
        self.driver = driver
        self.store = store
        self.lens = lens
        self.options = options
        self.total = options.count
        self.keepsClips = keepsClips
        self.clipDuration = clipDuration
    }

    /// "12 of 84"
    var progressText: String { "\(done) of \(total)" }

    /// Runs once. Each option is applied, recorded for `clipDuration`, stopped, and evaluated before the next begins.
    func run() async {
        guard !hasStarted else { return }
        hasStarted = true
        isRunning = true
        let startedAt = Date()
        for option in options {
            if isCancelled { break }
            rows.append(await sweep(option))
            done += 1
        }
        let report = SweepReport(startedAt: startedAt, finishedAt: Date(), lensID: lens.id, osBuild: DeviceIdentity.osBuild(),
                                 modelIdentifier: DeviceIdentity.modelIdentifier(), cancelled: done < total, rows: rows)
        reportURL = write(report)
        resultText = Self.resultText(report: report, done: done, total: total, reportURL: reportURL)
        isRunning = false
    }

    /// The clip being recorded finishes and is reported; no further option starts.
    func cancel() {
        guard isRunning else { return }
        isCancelled = true
    }

    /// The model forwards every recording result while the sweep runs.
    func recordingDidFinish(_ result: RecordingResult) {
        if let resultWaiter {
            self.resultWaiter = nil
            resultWaiter.resume(returning: result)
        } else {
            arrivedResult = result
        }
    }

    private func sweep(_ option: VideoOption) async -> SweepRow {
        guard let driver else {
            return SweepRow.evaluate(requested: option, facts: nil, error: SweepError.cameraGone(lensID: lens.id).description)
        }
        do throws(CameraSessionError) {
            try await driver.applySweepOption(option)
        } catch {
            return SweepRow.evaluate(requested: option, facts: nil, error: error.description)
        }
        arrivedResult = nil
        guard await driver.beginSweepClip() else {
            return SweepRow.evaluate(requested: option, facts: nil, error: SweepError.recordingDidNotStart(codec: option.codec.codecType).description)
        }
        // A clip that failed to start has already reported; otherwise record for the full length, even when cancelled.
        if arrivedResult == nil {
            do {
                try await Task.sleep(for: clipDuration)
            } catch {
                Self.logger.info("[FormatSweep:run] Clip wait cut short — {lens: \(self.lens.id, privacy: .public)}")
            }
            if arrivedResult == nil { driver.endSweepClip() }
        }
        let result = await nextResult()
        removeClip(result)
        return SweepRow.evaluate(requested: option, facts: result.sidecar?.actual, error: Self.errorText(result))
    }

    private func nextResult() async -> RecordingResult {
        if let arrivedResult {
            self.arrivedResult = nil
            return arrivedResult
        }
        return await withCheckedContinuation { resultWaiter = $0 }
    }

    /// Nil for a completed clip that could be read back; otherwise the error the row keeps in `detail`.
    private static func errorText(_ result: RecordingResult) -> String? {
        let file = result.url.lastPathComponent
        switch result.outcome {
        case .completed:
            guard result.sidecar?.actual == nil else { return nil }
            return result.sidecar?.error ?? SweepError.clipUnreadable(file: file).description
        case .stopped:
            return result.sidecar?.error ?? SweepError.stoppedEarly(file: file, outcome: result.outcome.summary).description
        case .failed(let message):
            return message
        }
    }

    /// Deletes the clip unless `-keepSweepClips on`; the sidecar stays.
    private func removeClip(_ result: RecordingResult) {
        guard !keepsClips else { return }
        let path = result.url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(at: result.url)
        } catch {
            Self.logger.error("\(SweepError.clipNotDeleted(path: path, reason: error.localizedDescription).description, privacy: .public)")
        }
    }

    private func write(_ report: SweepReport) -> URL? {
        let url = store.directory.appending(path: SweepReport.fileName(for: report.startedAt, timeZone: .current), directoryHint: .notDirectory)
        do {
            try report.encoded().write(to: url, options: .atomic)
            return url
        } catch {
            let failure = SweepError.reportUnwritable(path: url.path(percentEncoded: false), reason: error.localizedDescription)
            Self.logger.error("\(failure.description, privacy: .public)")
            return nil
        }
    }

    private static func resultText(report: SweepReport, done: Int, total: Int, reportURL: URL?) -> String {
        let outcome = report.cancelled ? "Cancelled after \(done) of \(total)." : "Done. \(report.summary)"
        let saved = reportURL.map { "Saved \($0.lastPathComponent)." } ?? "The report could not be saved."
        return "\(outcome) \(saved)"
    }
}
