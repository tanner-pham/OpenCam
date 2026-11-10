import CoreMedia
import Testing
@testable import OpenCam

@Suite struct ClipInspectorTests {
    @Test func droppedFramesNeverNegative() {
        #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 90) == 0); #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 85) == 5)
        #expect(ClipInspector.droppedFrames(durationSeconds: 3, frameRate: 30, frameCount: 92) == 0); #expect(ClipInspector.droppedFrames(durationSeconds: 2, frameRate: 24, frameCount: 47) == 1)
    }
    @Test func colourFromFormatExtensions() {
        #expect(ClipInspector.colour(primaries: nil, transfer: nil, log: kCMFormatDescriptionLogTransferFunction_AppleLog2 as String) == .appleLog2)
        #expect(ClipInspector.colour(primaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String, transfer: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String, log: nil) == .hlg)
        #expect(ClipInspector.colour(primaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String, transfer: kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String, log: nil) == .rec709)
        #expect(ClipInspector.colour(primaries: nil, transfer: nil, log: nil) == nil)
    }
}
