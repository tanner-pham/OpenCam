import Foundation

/// Holds the newest frame not yet drawn. A frame that arrives before the last one was drawn replaces it.
nonisolated struct FrameSlot<Frame: Sendable>: Sendable {
    /// Frames replaced before they were drawn.
    private(set) var dropped = 0
    private var frame: Frame?

    init() {}

    /// Replaces an undrawn frame, counting it in `dropped`.
    mutating func put(_ frame: Frame) {
        if self.frame != nil { dropped += 1 }
        self.frame = frame
    }

    /// The newest frame, once; nil until another arrives.
    mutating func take() -> Frame? {
        defer { frame = nil }
        return frame
    }

    /// Forgets an undrawn frame without counting it.
    mutating func empty() {
        frame = nil
    }
}
