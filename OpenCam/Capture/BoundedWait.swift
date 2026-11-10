import Foundation

/// One wait with a limit: it returns the first of the operation's value, a value passed to `finish`, or nil when the limit
/// passes. The operation itself is not cancelled (an awaited configure cannot be); a late value is ignored.
@MainActor final class BoundedWait<Value: Sendable> {
    private var continuation: CheckedContinuation<Value?, Never>?
    private var timer: Task<Void, Never>?

    /// With no operation, only `finish` or the limit ends the wait.
    func run(limit: Duration, _ operation: (@MainActor () async -> Value)? = nil) async -> Value? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startTimer(limit)
            if let operation {
                Task { [weak self] in
                    let value = await operation()
                    self?.finish(value)
                }
            }
        }
    }

    /// Ends the wait with `value`; nil ends it as if the limit had passed. Does nothing once the wait has ended.
    func finish(_ value: Value?) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        timer = nil
        continuation.resume(returning: value)
    }

    /// Brings the limit forward to `limit` from now, if the wait is still running.
    func shorten(to limit: Duration) {
        guard continuation != nil else { return }
        startTimer(limit)
    }

    private func startTimer(_ limit: Duration) {
        timer?.cancel()
        timer = Task { [weak self] in
            do {
                try await Task.sleep(for: limit)
            } catch {
                return
            }
            self?.finish(nil)
        }
    }
}
