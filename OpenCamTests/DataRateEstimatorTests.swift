import Testing
@testable import OpenCam

@Suite struct DataRateEstimatorTests {
    func opt(_ f: CodecFamily, _ q: String, _ t: BitrateTier?, _ w: Int, _ h: Int, _ fps: Int) -> VideoOption {
        VideoOption(lensID: "wide", codec: VideoCodec(family: f, quality: q, codecType: "x", bitrateTier: t), resolution: .named(width: w, height: h), frameRate: fps, colour: .rec709)
    }
    func mbps(_ o: VideoOption) -> Double { DataRateEstimator.megabitsPerSecond(for: o) }
    @Test func proResScalesByPixelsAndFrameRate() {
        #expect(abs(mbps(opt(.proRes, "422 HQ", nil, 1920, 1080, 30)) - 220.2202) < 0.001)
        #expect(abs(mbps(opt(.proRes, "422 HQ", nil, 3840, 2160, 30)) - 880.8809) < 0.001)
        #expect(abs(mbps(opt(.proRes, "422 Proxy", nil, 1920, 1080, 24)) - 36.0360) < 0.001)
    }
    @Test func hevcAndH264UseBitsPerPixel() {
        #expect(abs(mbps(opt(.hevc, "Max", .max, 3840, 2160, 30)) - 44.78976) < 0.0001)
        #expect(abs(mbps(opt(.hevc, "Low", .low, 1920, 1080, 120)) - 9.95328) < 0.0001)
        #expect(abs(mbps(opt(.h264, "High", .high, 3840, 2160, 30)) - 43.794432) < 0.0001)
    }
    @Test func remainingTimeKeepsTheReserve() {
        let hq = opt(.proRes, "422 HQ", nil, 3840, 2160, 30)
        #expect(abs(DataRateEstimator.gigabytesPerMinute(for: hq) - 6.6066) < 0.001)
        #expect(DataRateEstimator.minutesRemaining(freeBytes: 141_000_000_000, option: hq) == 21)
        #expect(DataRateEstimator.minutesRemaining(freeBytes: 1_500_000_000, option: hq) == 0)
        #expect(DataRateEstimator.footer(for: hq, freeBytes: 141_000_000_000) == "About 6.6 GB per minute. 21 min left.")
        #expect(DataRateEstimator.isLowStorage(minutes: 4)); #expect(!DataRateEstimator.isLowStorage(minutes: 5))
    }
}
