import Foundation

nonisolated enum DataRateEstimator {
    static let reserveBytes: Int64 = 2_000_000_000
    static let lowStorageMinutes = 5

    private static let referencePixels = 2_073_600.0
    private static let referenceFrameRate = 29.97
    private static let h264Factor = 1.6
    /// ProRes RAW has no published figure here; the 4444 XQ rate overstates it, so remaining time is never too long.
    private static let rawMbps = 500.0

    static func megabitsPerSecond(for option: VideoOption) -> Double {
        let pixels = Double(option.resolution.pixelCount)
        let fps = Double(option.frameRate)
        switch option.codec.family {
        case .raw:
            return scaledProRes(rawMbps, pixels: pixels, fps: fps)
        case .proRes:
            return scaledProRes(proResMbps(quality: option.codec.quality), pixels: pixels, fps: fps)
        case .hevc:
            return hevcMbps(option, pixels: pixels, fps: fps)
        case .h264:
            return hevcMbps(option, pixels: pixels, fps: fps) * h264Factor
        }
    }

    static func gigabytesPerMinute(for option: VideoOption) -> Double {
        megabitsPerSecond(for: option) * 60 / 8 / 1000
    }

    static func minutesRemaining(freeBytes: Int64, option: VideoOption) -> Int {
        let bytesPerMinute = gigabytesPerMinute(for: option) * 1_000_000_000
        guard bytesPerMinute > 0 else { return 0 }
        let usable = Double(max(freeBytes - reserveBytes, 0))
        return Int((usable / bytesPerMinute).rounded(.down))
    }

    static func isLowStorage(minutes: Int) -> Bool {
        minutes < lowStorageMinutes
    }

    static func footer(for option: VideoOption, freeBytes: Int64) -> String {
        let rate = String(format: "%.1f", gigabytesPerMinute(for: option))
        let minutes = minutesRemaining(freeBytes: freeBytes, option: option)
        return "About \(rate) GB per minute. \(minutes) min left."
    }

    private static func scaledProRes(_ mbps: Double, pixels: Double, fps: Double) -> Double {
        mbps * (pixels / referencePixels) * (fps / referenceFrameRate)
    }

    private static func proResMbps(quality: String) -> Double {
        let name = quality.lowercased()
        if name.contains("xq") { return 500 }
        if name.contains("4444") { return 330 }
        if name.contains("hq") { return 220 }
        if name.contains("lt") { return 102 }
        if name.contains("proxy") { return 45 }
        return 147
    }

    private static func hevcMbps(_ option: VideoOption, pixels: Double, fps: Double) -> Double {
        let tier = option.codec.bitrateTier ?? .high
        return tier.bitsPerPixelPerFrame * pixels * fps / 1e6
    }
}
