import Foundation

/// What `MovieRecorder` knows about its clips, kept as a value under one lock: the clip pending since `begin`, earlier
/// clips whose end was never reported (a restart ended them in the model), and finished files whose result is still
/// being read back. The output's callbacks are matched to a clip by `CaptureStore.clipKey`, never by whole URL.
nonisolated struct RecordingTracker: Sendable {
    private(set) var pending: PendingRecording?
    /// Clips replaced by a newer `begin` before their end was reported; a late report for one is matched here.
    private var unfinished: [PendingRecording] = []
    private var finishing = 0
    /// True once the output reports the pending clip writing.
    private var hasStarted = false
    /// A stop asked for before the pending clip started writing, applied when it does.
    private var isStopRequested = false

    /// Makes `recording` the pending clip; an earlier pending clip moves to `unfinished`.
    mutating func begin(_ recording: PendingRecording) {
        if let pending { unfinished.append(pending) }
        pending = recording
        hasStarted = false
        isStopRequested = false
    }

    /// The clip whose file at `url` finished, now finishing; `isCurrent` is false for a late report of an earlier clip,
    /// which leaves the pending clip alone. Nil when no clip was recorded to `url`.
    mutating func finish(url: URL) -> (recording: PendingRecording, isCurrent: Bool)? {
        let key = CaptureStore.clipKey(for: url)
        if let current = pending, CaptureStore.clipKey(for: current.url) == key {
            pending = nil
            hasStarted = false
            isStopRequested = false
            finishing += 1
            return (current, true)
        }
        guard let index = unfinished.firstIndex(where: { CaptureStore.clipKey(for: $0.url) == key }) else { return nil }
        finishing += 1
        return (unfinished.remove(at: index), false)
    }

    /// The output started writing `url`. True when a stop was asked for before, so the caller stops the output now.
    mutating func didStart(url: URL) -> Bool {
        guard let pending, CaptureStore.clipKey(for: pending.url) == CaptureStore.clipKey(for: url) else { return false }
        hasStarted = true
        return isStopRequested
    }

    /// A stop is applied at once once the pending clip is writing, and remembered until it is.
    mutating func requestStop() -> RecordingStop {
        if pending != nil {
            guard hasStarted else {
                isStopRequested = true
                return .deferred
            }
            return .stopNow
        }
        return finishing > 0 ? .awaitingResult : .nothingInFlight
    }

    /// A finished clip's result has been yielded.
    mutating func reported() {
        finishing -= 1
    }
}
