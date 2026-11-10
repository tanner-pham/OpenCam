import Synchronization

/// Counts calls from any thread, for tests that check how often a closure runs.
nonisolated final class CallCounter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func increment() { count.withLock { $0 += 1 } }
}
