import Foundation
import OSLog

/// The state of one run: the report so far, the progress count and the clock. Used by one task only.
nonisolated final class RawSizeCheckRun {
    static let captureTimeout = Duration.seconds(6)
    static let timeBudget = Duration.seconds(110)
    private static let logger = Logger(subsystem: "local.opencam.app", category: "RawSizeCheck")

    var report: RawSizeCheckReport
    let progress: RawSizeCheckProgress
    private var done = 0
    private var total = 0
    private let startedAt = ContinuousClock.now

    init(report: RawSizeCheckReport, progress: RawSizeCheckProgress) {
        self.report = report
        self.progress = progress
    }

    var isOverBudget: Bool { ContinuousClock.now - startedAt > Self.timeBudget }

    /// Trials planned so far; the total grows as each camera and route is known.
    nonisolated(nonsending) func plan(_ count: Int) async {
        total += count
        await progress.show(done: done, of: total)
    }

    nonisolated(nonsending) func record(_ trial: RawSizeCheckTrial) async {
        report.trials.append(trial)
        if let reason = trial.skipReason { Self.logger.info("Skipped — \(reason, privacy: .public)") }
        if let error = trial.capture?.error { report.errors.append(error) }
        done += 1
        save()
        await progress.show(done: done, of: max(total, done))
    }

    func addError(_ function: String, _ description: String, context: String) {
        let text = "[RawSizeCheck:\(function)] \(description) — {\(context)}"
        Self.logger.error("\(text, privacy: .public)")
        report.errors.append(text)
    }

    /// A report that could not be written is logged; the run goes on.
    func save() {
        report.refreshSummary()
        do {
            try RawSizeCheckStore.write(report)
        } catch {
            Self.logger.error("[RawSizeCheck:save] The report could not be written — {reason: \(error.localizedDescription, privacy: .public)}")
        }
    }
}
