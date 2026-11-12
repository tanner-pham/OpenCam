import Foundation

/// The undo and redo steps of one editing session. A step holds the edit as it was before a change; changes that follow each
/// other within `coalesceWindow` are one step, so a slider drag undoes in one go.
nonisolated struct EditHistory: Sendable {
    static let coalesceWindow: TimeInterval = 0.6
    static let limit = 100

    private var undoSteps: [PhotoEdit] = []
    private var redoSteps: [PhotoEdit] = []
    /// When the last change was recorded; nil after an undo, a redo or a clear, so the next change starts a step.
    private var lastRecorded: Date?

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }

    /// Notes a change; `before` is the edit as it was just ahead of it.
    mutating func record(_ before: PhotoEdit, at time: Date) {
        defer { lastRecorded = time }
        if let last = lastRecorded, time.timeIntervalSince(last) < Self.coalesceWindow { return }
        undoSteps.append(before)
        if undoSteps.count > Self.limit { undoSteps.removeFirst(undoSteps.count - Self.limit) }
        redoSteps.removeAll()
    }

    /// The edit one step back, or nil when there is none; `current` becomes the redo step.
    mutating func undo(from current: PhotoEdit) -> PhotoEdit? {
        guard let previous = undoSteps.popLast() else { return nil }
        redoSteps.append(current)
        lastRecorded = nil
        return previous
    }

    mutating func redo(from current: PhotoEdit) -> PhotoEdit? {
        guard let next = redoSteps.popLast() else { return nil }
        undoSteps.append(current)
        lastRecorded = nil
        return next
    }

    mutating func clear() {
        undoSteps.removeAll()
        redoSteps.removeAll()
        lastRecorded = nil
    }
}
