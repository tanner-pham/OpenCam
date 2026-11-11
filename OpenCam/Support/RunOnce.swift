import Foundation

/// Runs its body the first time `run` is called and never again, whichever of several triggers calls it first.
nonisolated struct RunOnce: Sendable, Equatable {
    private(set) var hasRun = false

    mutating func run(_ body: () -> Void) {
        guard !hasRun else { return }
        hasRun = true
        body()
    }
}
