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
            return proResMbps(option, pixels: pixels, fps: fps)
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
        let left = minutes > 0 ? "\(durationText(minutes: minutes)) left." : "No recording time left."
        return "About \(rateText(megabitsPerSecond(for: option))), \(rate) GB per minute. \(left)"
    }

    /// What a chip shows for `option`: the data rate, then the record time left in `freeBytes`.
    static func estimate(for option: VideoOption, freeBytes: Int64) -> ChipEstimate {
        let megabits = megabitsPerSecond(for: option)
        let minutes = minutesRemaining(freeBytes: freeBytes, option: option)
        return ChipEstimate(
            rate: chipRateText(megabits: megabits),
            time: chipTimeText(minutes: minutes),
            spoken: "about \(spokenRate(megabits)), \(spokenTime(minutes: minutes))"
        )
    }

    static func chipRateText(megabits: Double) -> String { "~" + rateText(megabits) }

    /// "~11h 17m" in the duration text; "Full" when no minutes are left.
    static func chipTimeText(minutes: Int) -> String {
        minutes > 0 ? "~" + durationText(minutes: minutes) : "Full"
    }

    /// "11h 17m", "21m": the system's narrow duration format. The chips, the settings footer and the camera's time-left slot
    /// all say a time left this way.
    static func durationText(minutes: Int) -> String { durationStyle(width: .narrow, minutes: minutes) }

    /// One decimal under 10 Mb/s, whole megabits up to 1000, then gigabits with one decimal.
    private static func rateText(_ megabits: Double) -> String {
        if megabits.rounded() >= 1000 { return String(format: "%.1f Gb/s", megabits / 1000) }
        if (megabits * 10).rounded() / 10 < 10 { return String(format: "%.1f Mb/s", megabits) }
        return String(format: "%.0f Mb/s", megabits)
    }

    private static func spokenRate(_ megabits: Double) -> String {
        rateText(megabits)
            .replacingOccurrences(of: " Mb/s", with: " megabits per second")
            .replacingOccurrences(of: " Gb/s", with: " gigabits per second")
    }

    private static func spokenTime(minutes: Int) -> String {
        minutes > 0 ? "about \(durationStyle(width: .wide, minutes: minutes)) of recording" : "no recording time left"
    }

    private static func durationStyle(width: Duration.UnitsFormatStyle.UnitWidth, minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: width))
    }

    private static func scaledProRes(_ mbps: Double, pixels: Double, fps: Double) -> Double {
        mbps * (pixels / referencePixels) * (fps / referenceFrameRate)
    }

    /// Apple's cell; else the same size's 30 fps cell scaled to the rate; else the linear estimate (other sizes, 4444 kinds).
    private static func proResMbps(_ option: VideoOption, pixels: Double, fps: Double) -> Double {
        let quality = option.codec.quality
        let size = option.resolution
        if let cell = ProResRateTable.megabitsPerSecond(quality: quality, width: size.width, height: size.height, frameRate: option.frameRate) {
            return cell
        }
        if let base = ProResRateTable.megabitsPerSecond(quality: quality, width: size.width, height: size.height, frameRate: 30) {
            return base * fps / 30
        }
        return scaledProRes(proResMbps(quality: quality), pixels: pixels, fps: fps)
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
