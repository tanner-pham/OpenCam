import AVFoundation
import Testing
@testable import OpenCam

@Suite struct MovieOutputSettingsTests {
    @Test func bitrateOnlyForTiersAndOnlyWhenAllowed() {
        let uhd = Resolution.named(width: 3840, height: 2160), keys = [AVVideoCodecKey, AVVideoCompressionPropertiesKey]
        let hevc = VideoOption(lensID: "w", codec: VideoCodec(family: .hevc, quality: "Max", codecType: "hvc1", bitrateTier: .max), resolution: uhd, frameRate: 30, colour: .rec709)
        #expect(MovieOutputSettings.make(for: hevc, supportedKeys: keys) == MovieOutputSettings(codecType: "hvc1", averageBitRate: 44_789_760))
        #expect(MovieOutputSettings.make(for: hevc, supportedKeys: [AVVideoCodecKey]).averageBitRate == nil)
        let hq = VideoOption(lensID: "w", codec: VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil), resolution: uhd, frameRate: 30, colour: .appleLog2)
        #expect(MovieOutputSettings.make(for: hq, supportedKeys: keys).averageBitRate == nil)
    }
}
