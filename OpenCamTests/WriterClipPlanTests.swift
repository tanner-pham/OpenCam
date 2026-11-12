import Foundation
import Testing
@testable import OpenCam

@Suite struct WriterClipPlanTests {
    let url = URL(filePath: "/tmp/OC_0001.MOV")
    let uhd = Resolution.named(width: 3840, height: 2160)

    func option(_ codec: VideoCodec, colour: ColourMode) -> VideoOption {
        VideoOption(lensID: "w", codec: codec, resolution: uhd, frameRate: 30, colour: colour)
    }

    @Test func aProResPlanHasNoBitRate() {
        let hq = VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil)
        let plan = WriterClipPlan.make(option: option(hq, colour: .hlg), url: url, bufferWidth: 3840, bufferHeight: 2160,
                                       rotationDegrees: 90, policy: .keepRecording, minFreeBytes: 2_000_000_000)
        #expect(plan.codecType == "apch")
        #expect(plan.averageBitRate == nil)
        #expect(!plan.bakesLog)
        #expect(plan.frameRate == 30)
    }

    @Test func anHEVCLogPlanCarriesItsTierAndBakes() {
        let high = VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high)
        let chosen = option(high, colour: .log)
        let plan = WriterClipPlan.make(option: chosen, url: url, bufferWidth: 3840, bufferHeight: 2160,
                                       rotationDegrees: 0, policy: .stopRecording, minFreeBytes: 1)
        #expect(plan.codecType == "hvc1")
        #expect(plan.averageBitRate == Int((DataRateEstimator.megabitsPerSecond(for: chosen) * 1e6).rounded()))
        #expect(plan.averageBitRate != nil)
        #expect(plan.bakesLog)
        #expect(plan.policy == .stopRecording)
        #expect(plan.minFreeBytes == 1)
        let rec709 = WriterClipPlan.make(option: option(high, colour: .hlg), url: url, bufferWidth: 3840, bufferHeight: 2160,
                                         rotationDegrees: 0, policy: .keepRecording, minFreeBytes: 0)
        #expect(!rec709.bakesLog)
    }

    @Test func rotationAndSizeComeFromTheCaller() {
        let proxy = VideoCodec(family: .proRes, quality: "422 Proxy", codecType: "apco", bitrateTier: nil)
        let plan = WriterClipPlan.make(option: option(proxy, colour: .rec709), url: url, bufferWidth: 1920, bufferHeight: 1080,
                                       rotationDegrees: 270, policy: .keepRecording, minFreeBytes: 0)
        #expect(plan.width == 1920)
        #expect(plan.height == 1080)
        #expect(plan.rotationDegrees == 270)
        #expect(plan.url == url)
    }
}
