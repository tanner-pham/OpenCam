import Observation

/// What the screen of a `-rawSizeCheck` launch shows: one line of text.
@Observable
final class RawSizeCheckProgress {
    private(set) var line = "RAW size check: starting"
    private(set) var isFinished = false

    func show(done: Int, of total: Int) {
        guard !isFinished else { return }
        line = "RAW size check: \(done) of \(total)"
    }

    func finish() {
        isFinished = true
        line = "RAW size check finished."
    }
}
