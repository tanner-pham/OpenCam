import Foundation
import Observation
import OSLog

/// Records a short clip in each option, one at a time, compares each file with the request, and writes a report.
/// Every camera step goes through `driver`, so the model's configure queue and recording rules stay in charge.
/// No step waits without a limit: a step that passes its deadline fails the row with "The clip did not finish.",
/// any recording still running is stopped, and the sweep moves on; two such rows in a row end the sweep early.
/// The sweep also ends early when the driver's camera is interrupted or stopped; the row it was on then is no answer.
/// A failing option is recorded and the sweep moves on; restoring the user's selection is the model's job.
@MainActor @Observable final class FormatSweep {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "FormatSweep")
    /// Rows in a row that may pass their deadline before the sweep stops itself.
    static let timeoutsBeforeStopping = 2

    private(set) var done = 0
    let total: Int
    private(set) var rows: [SweepRow] = []
    private(set) var isRunning = false
    private(set) var reportURL: URL?
    /// Nil until the sweep ends; then "Done. 80 passed, 4 failed. Saved sweep-….json.", "Cancelled after 12 of 84. Saved
    /// sweep-….json." or "Stopped after 12 of 84. The camera stopped responding. Saved sweep-….json.".
    private(set) var resultText: String?

    let deadlines: SweepDeadlines
    @ObservationIgnored private weak var driver: (any SweepDriver)?
    @ObservationIgnored private let store: CaptureStore
    @ObservationIgnored private let lens: Lens
    @ObservationIgnored private let options: [VideoOption]
    @ObservationIgnored private let keepsClips: Bool
    @ObservationIgnored private let clipDuration: Duration
    @ObservationIgnored private var isCancelled = false
    @ObservationIgnored private var hasStarted = false
    /// The option being recorded; a result for any other option is a late one from a row that already timed out.
    @ObservationIgnored private var currentOption: VideoOption?
    /// A result for `currentOption` that arrived before the sweep waited for it, such as a recording that failed to start.
    @ObservationIgnored private var arrivedResult: RecordingResult?
    /// The wait for `currentOption`'s result, while it runs.
    @ObservationIgnored private var resultWait: BoundedWait<RecordingResult>?
    /// Shortens whichever wait is running, so Cancel never waits on a full deadline.
    @ObservationIgnored private var shortenActiveWait: ((Duration) -> Void)?

    init(driver: any SweepDriver, store: CaptureStore, lens: Lens, options: [VideoOption], keepsClips: Bool,
         clipDuration: Duration = .seconds(SweepRow.clipSeconds), deadlines: SweepDeadlines = .standard) {
        self.driver = driver
        self.store = store
        self.lens = lens
        self.options = options
        self.total = options.count
        self.keepsClips = keepsClips
        self.clipDuration = clipDuration
        self.deadlines = deadlines
    }

    /// "12 of 84"
    var progressText: String { "\(done) of \(total)" }

    /// Runs once. Each option is applied, recorded for `clipDuration`, stopped, and evaluated before the next begins.
    func run() async {
        guard !hasStarted else { return }
        hasStarted = true
        isRunning = true
        let startedAt = Date()
        var timeoutsInARow = 0
        var isEndedEarly = false
        for option in options {
            if isCancelled { break }
            // An interrupted or stopped camera fails every clip at once, so the sweep ends rather than record false failures.
            if let driver, !driver.isCameraUsable {
                isEndedEarly = true
                break
            }
            let (attempted, isTimedOut) = await sweep(option)
            guard var row = attempted else {
                // An earlier clip is still recording, so the camera has stopped responding; this option was never tried.
                isEndedEarly = true
                break
            }
            let isCameraUsable = driver?.isCameraUsable ?? true
            if !isCameraUsable { row = row.recordedWithoutCamera() }
            rows.append(row)
            done += 1
            if !isCameraUsable {
                isEndedEarly = true
                break
            }
            timeoutsInARow = isTimedOut ? timeoutsInARow + 1 : 0
            if timeoutsInARow >= Self.timeoutsBeforeStopping {
                isEndedEarly = true
                break
            }
        }
        currentOption = nil
        let report = SweepReport(startedAt: startedAt, finishedAt: Date(), lensID: lens.id, osBuild: DeviceIdentity.osBuild(),
                                 modelIdentifier: DeviceIdentity.modelIdentifier(), cancelled: !isEndedEarly && done < total,
                                 endedEarly: isEndedEarly, rows: rows)
        reportURL = write(report)
        resultText = Self.resultText(report: report, done: done, total: total, reportURL: reportURL)
        isRunning = false
    }

    /// No further option starts. The clip being recorded still finishes, but any wait now ends within `cancelGrace`.
    func cancel() {
        guard isRunning, !isCancelled else { return }
        isCancelled = true
        shortenActiveWait?(deadlines.cancelGrace)
    }

    /// The model forwards every recording result while the sweep runs. A late result from a row that timed out is dropped.
    func recordingDidFinish(_ result: RecordingResult) {
        guard let currentOption, result.option == currentOption else {
            removeClip(result)
            return
        }
        if let resultWait {
            resultWait.finish(result)
        } else {
            arrivedResult = result
        }
    }

    /// The row, and whether it passed a deadline. No row when the option could not be applied because an earlier clip
    /// is still recording.
    private func sweep(_ option: VideoOption) async -> (SweepRow?, Bool) {
        currentOption = option
        arrivedResult = nil
        guard let driver else {
            return (SweepRow.evaluate(requested: option, facts: nil, error: SweepError.cameraGone(lensID: lens.id).description), false)
        }
        let applyWait = BoundedWait<Result<Void, CameraSessionError>>()
        let applied = await bounded(applyWait, limit: deadlines.start) {
            do throws(CameraSessionError) {
                try await driver.applySweepOption(option)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        guard let applied else { return timedOut(option, step: "configure", driver: driver) }
        if case .failure(let error) = applied {
            if case .recordingInProgress = error { return (nil, false) }
            return (SweepRow.evaluate(requested: option, facts: nil, error: error.description), false)
        }
        let startWait = BoundedWait<Bool>()
        guard let started = await bounded(startWait, limit: deadlines.start, { await driver.beginSweepClip() }) else {
            return timedOut(option, step: "start", driver: driver)
        }
        guard started else {
            return (SweepRow.evaluate(requested: option, facts: nil, error: SweepError.recordingDidNotStart(codec: option.codec.codecType).description), false)
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
        let result: RecordingResult
        if let arrivedResult {
            self.arrivedResult = nil
            result = arrivedResult
        } else {
            let wait = BoundedWait<RecordingResult>()
            resultWait = wait
            let finished = await bounded(wait, limit: deadlines.finish)
            resultWait = nil
            guard let finished else { return timedOut(option, step: "finish", driver: driver) }
            result = finished
        }
        removeClip(result)
        return (SweepRow.evaluate(requested: option, facts: result.sidecar?.actual, error: Self.errorText(result)), false)
    }

    /// Runs `wait`, ending it early when the sweep is or becomes cancelled.
    private func bounded<Value: Sendable>(_ wait: BoundedWait<Value>, limit: Duration,
                                          _ operation: (@MainActor () async -> Value)? = nil) async -> Value? {
        shortenActiveWait = { [weak wait] grace in wait?.shorten(to: grace) }
        defer { shortenActiveWait = nil }
        return await wait.run(limit: isCancelled ? min(limit, deadlines.cancelGrace) : limit, operation)
    }

    /// Stops any recording still running and fails the row.
    private func timedOut(_ option: VideoOption, step: String, driver: any SweepDriver) -> (SweepRow?, Bool) {
        let detail = SweepError.deadlinePassed(step: step, codec: option.codec.codecType).description
        Self.logger.error("\(detail, privacy: .public)")
        driver.endSweepClip()
        return (SweepRow.timedOut(requested: option, detail: detail), true)
    }

    /// Nil for a completed clip that could be read back; otherwise the error the row keeps in `detail`.
    private static func errorText(_ result: RecordingResult) -> String? {
        let file = result.url.lastPathComponent
        switch result.outcome {
        case .completed:
            guard result.sidecar?.actual == nil else { return nil }
            return result.sidecar?.error ?? SweepError.clipUnreadable(file: file).description
        case .stopped, .nothingRecorded:
            return result.sidecar?.error ?? SweepError.stoppedEarly(file: file, outcome: result.outcome.summary).description
        case .failed(let message):
            return message
        }
    }

    /// Deletes the clip unless `-keepSweepClips on`; the sidecar stays.
    private func removeClip(_ result: RecordingResult) {
        guard !keepsClips else { return }
        Self.removeClip(at: result.url)
    }

    /// Deletes a sweep clip, if it exists; its sidecar stays. A failure is logged.
    static func removeClip(at url: URL) {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
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
        let outcome = if report.endedEarly {
            "Stopped after \(done) of \(total). The camera stopped responding."
        } else if report.cancelled {
            "Cancelled after \(done) of \(total)."
        } else {
            "Done. \(report.summary)"
        }
        let saved = reportURL.map { "Saved \($0.lastPathComponent)." } ?? "The report could not be saved."
        return "\(outcome) \(saved)"
    }
}
