import Foundation

/// Elapsed time as HH:MM:SS:FF at a whole frame rate.
nonisolated enum Timecode {
    static func string(elapsed: TimeInterval, frameRate: Int) -> String {
        let rate = max(frameRate, 1)
        let frames = Int((max(elapsed, 0) * Double(rate)).rounded(.down))
        let seconds = frames / rate
        return String(format: "%02d:%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60, frames % rate)
    }
}
