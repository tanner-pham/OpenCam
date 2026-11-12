import AVFoundation
import Testing
@testable import OpenCam

@Suite struct ColourModeTests {
    /// Each colour against the SDK's own constant, written out so a wrong mapping cannot agree with itself.
    /// Log is baked from HLG frames, so it records in the HLG capture colour space and is never read back from one.
    let expected: [ColourMode: AVCaptureColorSpace] = [
        .rec709: .sRGB, .p3: .P3_D65, .hlg: .HLG_BT2020, .log: .HLG_BT2020, .appleLog: .appleLog, .appleLog2: .appleLog2,
    ]

    @Test func everyColourRoundTripsThroughItsCaptureColourSpace() throws {
        #expect(Set(expected.keys) == Set(ColourMode.allCases))
        for colour in ColourMode.allCases {
            let space = try #require(expected[colour])
            #expect(colour.captureColorSpaceRawValue == space.rawValue)
            // Log shares HLG's raw value; reading a capture colour space back gives HLG.
            #expect(ColourMode(captureColorSpace: space.rawValue) == (colour == .log ? .hlg : colour))
            #expect(ColourMode(captureColorSpace: colour.captureColorSpaceRawValue) == (colour == .log ? .hlg : colour))
        }
        #expect(ColourMode(captureColorSpace: -1) == nil); #expect(ColourMode(captureColorSpace: 99) == nil)
    }

    @Test func theColoursAreListedInRowOrder() {
        #expect(ColourMode.allCases == [.rec709, .p3, .hlg, .log, .appleLog, .appleLog2])
        #expect(ColourMode.allCases.map(\.rawValue) == ["Rec. 709", "P3", "HLG", "Log", "Apple Log", "Apple Log 2"])
        #expect(ColourMode.log.captureColorSpaceRawValue == 2)
        #expect(ColourMode(captureColorSpace: 2) == .hlg)
        #expect(ColourMode.allCases.map(\.shortName) == ["Rec. 709", "P3", "HLG", "Log", "Apple Log", "Apple Log 2"])
    }
}
