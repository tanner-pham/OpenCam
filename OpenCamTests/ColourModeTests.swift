import AVFoundation
import Testing
@testable import OpenCam

@Suite struct ColourModeTests {
    /// Each colour against the SDK's own constant, written out so a wrong mapping cannot agree with itself.
    let expected: [ColourMode: AVCaptureColorSpace] = [
        .rec709: .sRGB, .p3: .P3_D65, .hlg: .HLG_BT2020, .appleLog: .appleLog, .appleLog2: .appleLog2,
    ]

    @Test func everyColourRoundTripsThroughItsCaptureColourSpace() throws {
        #expect(Set(expected.keys) == Set(ColourMode.allCases))
        for colour in ColourMode.allCases {
            let space = try #require(expected[colour])
            #expect(colour.captureColorSpaceRawValue == space.rawValue)
            #expect(ColourMode(captureColorSpace: space.rawValue) == colour)
            #expect(ColourMode(captureColorSpace: colour.captureColorSpaceRawValue) == colour)
        }
        #expect(ColourMode(captureColorSpace: -1) == nil); #expect(ColourMode(captureColorSpace: 99) == nil)
    }
}
