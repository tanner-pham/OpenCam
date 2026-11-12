import Testing
@testable import OpenCam

@Suite struct DataRateEstimatorTests {
    func opt(_ f: CodecFamily, _ q: String, _ t: BitrateTier?, _ w: Int, _ h: Int, _ fps: Int) -> VideoOption {
        VideoOption(lensID: "wide", codec: VideoCodec(family: f, quality: q, codecType: "x", bitrateTier: t), resolution: .named(width: w, height: h), frameRate: fps, colour: .rec709)
    }
    func mbps(_ o: VideoOption) -> Double { DataRateEstimator.megabitsPerSecond(for: o) }
    @Test func proResUsesApplesTable() {
        #expect(mbps(opt(.proRes, "422 HQ", nil, 1920, 1080, 30)) == 220)
        #expect(mbps(opt(.proRes, "422 HQ", nil, 3840, 2160, 30)) == 884)
        #expect(mbps(opt(.proRes, "422 HQ", nil, 1280, 720, 30)) == 110)
        #expect(mbps(opt(.proRes, "422 Proxy", nil, 1920, 1080, 24)) == 36)
        #expect(abs(mbps(opt(.proRes, "422 HQ", nil, 3840, 2160, 48)) - 1414.4) < 0.001)
        #expect(abs(mbps(opt(.proRes, "422 HQ", nil, 1920, 1440, 30)) - 293.63) < 0.01)
    }
    @Test func hevcAndH264UseBitsPerPixel() {
        #expect(abs(mbps(opt(.hevc, "Max", .max, 3840, 2160, 30)) - 44.78976) < 0.0001)
        #expect(abs(mbps(opt(.hevc, "Low", .low, 1920, 1080, 120)) - 9.95328) < 0.0001)
        #expect(abs(mbps(opt(.h264, "High", .high, 3840, 2160, 30)) - 43.794432) < 0.0001)
    }
    @Test func remainingTimeKeepsTheReserve() {
        let hq = opt(.proRes, "422 HQ", nil, 3840, 2160, 30)
        #expect(abs(DataRateEstimator.gigabytesPerMinute(for: hq) - 6.63) < 0.001)
        #expect(DataRateEstimator.minutesRemaining(freeBytes: 141_000_000_000, option: hq) == 20)
        #expect(DataRateEstimator.minutesRemaining(freeBytes: 1_500_000_000, option: hq) == 0)
        #expect(DataRateEstimator.footer(for: hq, freeBytes: 141_000_000_000) == "About 884 Mb/s, 6.6 GB per minute. 20m left.")
        #expect(DataRateEstimator.isLowStorage(minutes: 4)); #expect(!DataRateEstimator.isLowStorage(minutes: 5))
    }

    @Test func chipRateTextRoundsByMagnitude() {
        #expect(DataRateEstimator.chipRateText(megabits: 7.5) == "~7.5 Mb/s")
        #expect(DataRateEstimator.chipRateText(megabits: 44.79) == "~45 Mb/s")
        #expect(DataRateEstimator.chipRateText(megabits: 147) == "~147 Mb/s")
        #expect(DataRateEstimator.chipRateText(megabits: 1200) == "~1.2 Gb/s")
        #expect(DataRateEstimator.chipRateText(megabits: 999.7) == "~1.0 Gb/s")
        #expect(DataRateEstimator.chipRateText(megabits: 9.97) == "~10 Mb/s")
    }
    @Test func chipTimeTextUsesTheSystemDurationFormat() {
        func system(_ minutes: Int) -> String {
            "~" + Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
        #expect(DataRateEstimator.chipTimeText(minutes: 0) == "Full")
        #expect(DataRateEstimator.chipTimeText(minutes: 45) == system(45))
        #expect(DataRateEstimator.chipTimeText(minutes: 677) == system(677))
        #expect(DataRateEstimator.chipTimeText(minutes: 45).hasPrefix("~45"))
        #expect(DataRateEstimator.chipTimeText(minutes: 677).hasPrefix("~11"))
        #expect(DataRateEstimator.chipTimeText(minutes: 677).contains("17"))
    }
    /// One fact, one wording: the chips, the footer and the camera's time-left slot all use this text.
    @Test func durationTextIsTheSystemNarrowDurationWithoutATilde() {
        #expect(DataRateEstimator.durationText(minutes: 677) == "11h 17m")
        #expect(DataRateEstimator.durationText(minutes: 21) == "21m")
        #expect(DataRateEstimator.durationText(minutes: 45) == "45m")
        #expect(DataRateEstimator.chipTimeText(minutes: 677) == "~" + DataRateEstimator.durationText(minutes: 677))
    }
    @Test func footerSaysNoRecordingTimeLeftAtZero() {
        let hevc = opt(.hevc, "Max", .max, 3840, 2160, 30)
        #expect(DataRateEstimator.footer(for: hevc, freeBytes: 0) == "About 45 Mb/s, 0.3 GB per minute. No recording time left.")
    }
    @Test func estimateCarriesTheTwoLinesAndTheSpokenForm() {
        let hevc = opt(.hevc, "Max", .max, 3840, 2160, 30)
        let free = DataRateEstimator.reserveBytes + 677 * 336_000_000
        let minutes = DataRateEstimator.minutesRemaining(freeBytes: free, option: hevc)
        let estimate = DataRateEstimator.estimate(for: hevc, freeBytes: free)
        #expect(estimate.rate == "~45 Mb/s")
        #expect(estimate.time == DataRateEstimator.chipTimeText(minutes: minutes))
        #expect(estimate.spoken.hasPrefix("about 45 megabits per second, about "))
        #expect(estimate.spoken.hasSuffix(" of recording"))
        let full = DataRateEstimator.estimate(for: hevc, freeBytes: 0)
        #expect(full.time == "Full")
        #expect(full.spoken == "about 45 megabits per second, no recording time left")
        let fast = DataRateEstimator.estimate(for: opt(.proRes, "4444 XQ", nil, 3840, 2160, 30), freeBytes: 0)
        #expect(fast.spoken.hasPrefix("about 2.0 gigabits per second"))
    }
    @Test func footerStatesTheRateWithoutATilde() {
        let hevc = opt(.hevc, "Max", .max, 3840, 2160, 30)
        let free = DataRateEstimator.reserveBytes + 100 * 336_000_000
        let minutes = DataRateEstimator.minutesRemaining(freeBytes: free, option: hevc)
        #expect(DataRateEstimator.footer(for: hevc, freeBytes: free) == "About 45 Mb/s, 0.3 GB per minute. \(DataRateEstimator.durationText(minutes: minutes)) left.")
    }
}
