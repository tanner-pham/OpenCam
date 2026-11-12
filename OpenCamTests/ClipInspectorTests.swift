import CoreMedia
import Testing
@testable import OpenCam

@Suite struct ClipInspectorTests {
    @Test func droppedFramesNeverNegative() {
        #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 90) == 0); #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 85) == 5)
        #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 92) == 0); #expect(ClipInspector.droppedFrames(durationSeconds: 2, frameRate: 24, frameCount: 47) == 1)
    }
    @Test func unknownFrameCountGivesUnknownDroppedFrames() {
        #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: nil) == nil)
    }
    @Test func unknownFrameCountIsAbsentFromTheSidecar() throws {
        let option = VideoOption(lensID: "w", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high),
                                 resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
        let facts = ClipFacts(codecFourCC: "hvc1", width: 3840, height: 2160, nominalFrameRate: 30, durationSeconds: 3, frameCount: nil,
                              droppedFrames: nil, colour: .rec709, megabitsPerSecond: 27, hasAudio: true)
        let json = try #require(String(data: try ClipSidecar(requested: option, actual: facts, outcome: "completed", recordedAt: Date(), error: nil).encoded(), encoding: .utf8))
        #expect(!json.contains("frameCount")); #expect(!json.contains("droppedFrames")); #expect(json.contains("durationSeconds"))
    }
    @Test func colourFromFormatExtensions() {
        #expect(ClipInspector.colour(primaries: nil, transfer: nil, log: kCMFormatDescriptionLogTransferFunction_AppleLog2 as String) == .appleLog2)
        #expect(ClipInspector.colour(primaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String, transfer: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String, log: nil) == .hlg)
        #expect(ClipInspector.colour(primaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String, transfer: kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String, log: nil) == .rec709)
        #expect(ClipInspector.colour(primaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String, transfer: kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String, log: nil) == .log)
        #expect(ClipInspector.colour(primaries: nil, transfer: nil, log: nil) == nil)
    }
}
