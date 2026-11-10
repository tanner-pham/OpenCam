import Foundation
import Testing
@testable import OpenCam

@Suite struct CaptureHelpersTests {
    @Test func frameRatesCollapseToTheStandardList() {
        #expect(StandardFrameRates.collapse([1...30]) == [24, 25, 30]); #expect(StandardFrameRates.collapse([1...60]) == [24, 25, 30, 48, 50, 60])
        #expect(StandardFrameRates.collapse([1...30, 120...120]) == [24, 25, 30, 120]); #expect(StandardFrameRates.collapse([23.976...29.97]) == [24, 25, 30])
        #expect(StandardFrameRates.collapse([]) == [])
    }
    @Test func coloursAndLensLabels() {
        #expect([0, 1, 2, 3, 4].compactMap(ColourMode.init(captureColorSpace:)) == [.rec709, .p3, .hlg, .appleLog, .appleLog2])
        #expect(LensLabel.text(kind: .wide, zoomFactor: 2, localizedName: "Back Camera") == "2x")
        #expect(LensLabel.text(kind: .ultraWide, zoomFactor: 1, localizedName: "Back Ultra Wide Camera") == "0.5x")
        #expect(LensLabel.text(kind: .outerUltraWide, zoomFactor: 1, localizedName: "Front Camera") == "Front Camera")
    }
    @Test func interruptionNotices() {
        #expect(InterruptionReason(avReason: 3) == .cameraInUse); #expect(InterruptionReason.cameraInUse.notice == "Camera paused. Another app is using it.")
        #expect(InterruptionReason(avReason: 1).notice == nil); #expect(InterruptionReason(avReason: 99) == .other)
    }
}
