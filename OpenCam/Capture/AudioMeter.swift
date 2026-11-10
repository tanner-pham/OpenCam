import Foundation

/// Maps a channel's average power to a meter level.
nonisolated enum AudioMeter {
    private static let floorDecibels: Float = -60

    /// -60 dB and below is 0, 0 dB and above is 1, linear between.
    static func level(decibels: Float) -> Double {
        guard !decibels.isNaN else { return 0 }
        let level = Double((decibels - floorDecibels) / -floorDecibels)
        return min(max(level, 0), 1)
    }
}
