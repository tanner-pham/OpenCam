import Foundation
import Testing
@testable import OpenCam

@Suite struct CaptureCapabilitiesTests {
    @Test func fixtureLoadsWithExpectedCounts() throws {
        let caps = try CaptureCapabilities.bundledFixture()
        #expect(caps.lenses.map(\.id) == ["ultraWide", "wide", "wide@2", "outer", "inner"])
        #expect(caps.videoOptions(forLens: "wide").count == 352); #expect(caps.videoOptions(forLens: "ultraWide").count == 304)
        #expect(caps.videoOptions(forLens: "outer").count == 48); #expect(caps.photoOptions(forLens: "wide").count == 6)
        #expect(caps.photoOptions(forLens: "wide@2").map(\.format) == [.heif])
        #expect(Set(caps.videoOptions).count == caps.videoOptions.count)
    }
    @Test func codableRoundTripIsLossless() throws {
        let caps = try CaptureCapabilities.bundledFixture()
        #expect(try CaptureCapabilities.decode(caps.encoded()) == caps)
        #expect(throws: CapabilityError.self) { try CaptureCapabilities.decode(Data("{".utf8)) }
    }
    @Test func namesAndLabels() {
        #expect(Resolution.named(width: 3840, height: 2160).label == "4K"); #expect(Resolution.named(width: 4032, height: 3024).label == "Open gate")
        #expect(Resolution.named(width: 2000, height: 1000).label == "2000 × 1000")
        #expect(Resolution.named(width: 3840, height: 2160).detail == "3840 × 2160")
        #expect(PhotoOption(lensID: "wide", format: .raw, width: 8064, height: 6048).label == "48 MP")
        #expect(ColourMode(captureColorSpace: 4) == .appleLog2); #expect(ColourMode(captureColorSpace: 9) == nil)
        #expect(VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil).displayName == "ProRes 422 HQ")
    }
}
