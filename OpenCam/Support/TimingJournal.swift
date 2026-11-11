import Foundation

/// Slow moments, written to the error journal (`Documents/opencam-errors.log`) as one `[timing]` line each, so real numbers
/// can be read off the phone. Nothing is written, and no text is built, unless a duration passes its threshold; nothing runs
/// in between.
nonisolated enum TimingJournal {
    /// A main-actor turn longer than this drops a frame at 60 Hz.
    static let mainActorThreshold = Duration.milliseconds(16)
    /// A configure is a camera change on the session's queue; one this long shows as a paused picture.
    static let configureThreshold = Duration.milliseconds(100)

    /// Writes `[timing] <what> <ms> ms` when the time since `start` passes `threshold`.
    static func record(_ what: @autoclosure () -> String, since start: ContinuousClock.Instant, over threshold: Duration) {
        let elapsed = ContinuousClock.now - start
        guard elapsed > threshold else { return }
        ErrorJournal.record("[timing] \(what()) \(milliseconds(elapsed)) ms")
    }

    /// For the session: `configure photo 1x (mode, format)`, naming what differs from the configuration before it.
    static func configure(_ configuration: SessionConfiguration, after previous: SessionConfiguration?, since start: ContinuousClock.Instant) {
        record(describe(configuration, after: previous), since: start, over: configureThreshold)
    }

    static func describe(_ configuration: SessionConfiguration, after previous: SessionConfiguration?) -> String {
        let base = "configure \(configuration.mode.rawValue) \(configuration.lens.label)"
        guard let previous else { return base + " (first)" }
        var changed: [String] = []
        if previous.mode != configuration.mode { changed.append("mode") }
        if previous.lens.id != configuration.lens.id { changed.append("lens") }
        if previous.video != configuration.video || previous.photo != configuration.photo { changed.append("format") }
        if previous.includesAudio != configuration.includesAudio || previous.needsFrames != configuration.needsFrames {
            changed.append("outputs")
        }
        return base + " (\(changed.isEmpty ? "same" : changed.joined(separator: ", ")))"
    }

    static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }
}
