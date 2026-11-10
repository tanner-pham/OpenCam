import Foundation

/// How long each step of a format sweep may take before its row fails with "The clip did not finish.".
nonisolated struct SweepDeadlines: Sendable, Equatable {
    /// Applying an option (one session reconfigure, a second or two even across lenses) and starting its recording;
    /// also bounds restoring the user's selection afterwards.
    var start: Duration
    /// From the stop request to the result: finishing the file, reading it back and writing its sidecar. A 3 s ProRes
    /// 4444 XQ 4K clip is well under 1 GB already on disk, so this normally takes a second or two.
    var finish: Duration
    /// After Cancel, a wait still running ends within this, so a normal clip still finishes and a stuck one does not hold the sweep.
    var cancelGrace: Duration

    static let standard = SweepDeadlines(start: .seconds(15), finish: .seconds(30), cancelGrace: .seconds(5))
}
