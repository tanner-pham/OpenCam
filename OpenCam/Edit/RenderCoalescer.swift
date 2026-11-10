import Foundation

/// Keeps slider renders to one at a time: a value that arrives while a render runs replaces the waiting one, and when the
/// render finishes only the latest waiting value starts. Each started render gets a higher generation than the one before,
/// so a result can be checked against what is already on screen.
nonisolated struct RenderCoalescer<Value: Sendable>: Sendable {
    private var isRunning = false
    private var pending: Value?
    private var lastGeneration = 0

    /// No render runs and none waits.
    var isIdle: Bool { !isRunning && pending == nil }

    /// The render to start now, or nil when one is running; the value then waits in place of any earlier one.
    mutating func request(_ value: Value) -> (generation: Int, value: Value)? {
        guard !isRunning else {
            pending = value
            return nil
        }
        return start(value)
    }

    /// Call when the running render ends. The latest waiting value to render next, or nil when nothing waits.
    mutating func finish() -> (generation: Int, value: Value)? {
        isRunning = false
        guard let next = pending else { return nil }
        pending = nil
        return start(next)
    }

    private mutating func start(_ value: Value) -> (generation: Int, value: Value) {
        isRunning = true
        lastGeneration += 1
        return (lastGeneration, value)
    }
}
