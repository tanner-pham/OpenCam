import Foundation

/// What `MovieRecorder` knows about its clips, kept as a value under one lock: the clip pending since `begin`, earlier
/// clips whose end was never reported (a restart ended them in the model), and finished files whose result is still
/// being read back. The output's callbacks are matched to a clip by file URL.
nonisolated struct RecordingTracker: Sendable {
    private(set) var pending: PendingRecording?
    /// Clips replaced by a newer `begin` before their end was reported; a late report for one is matched here.
    private var unfinished: [PendingRecording] = []
    private var finishing = 0

    /// True from `begin` until the pending clip's result is reported.
    var isAwaitingResult: Bool { pending != nil || finishing > 0 }

    /// Makes `recording` the pending clip; an earlier pending clip moves to `unfinished`.
    mutating func begin(_ recording: PendingRecording) {
        if let pending { unfinished.append(pending) }
        pending = recording
    }

    /// The clip whose file at `url` finished, now finishing; `isCurrent` is false for a late report of an earlier clip,
    /// which leaves the pending clip alone. Nil when no clip was recorded to `url`.
    mutating func finish(url: URL) -> (recording: PendingRecording, isCurrent: Bool)? {
        if let current = pending, current.url == url {
            pending = nil
            finishing += 1
            return (current, true)
        }
        guard let index = unfinished.firstIndex(where: { $0.url == url }) else { return nil }
        finishing += 1
        return (unfinished.remove(at: index), false)
    }

    /// A finished clip's result has been yielded.
    mutating func reported() {
        finishing -= 1
    }
}
