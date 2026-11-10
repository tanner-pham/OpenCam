import Testing
@testable import OpenCam

@Suite struct LaunchConfigTests {
    @Test func parsesEveryFlag() {
        let c = LaunchConfig.parse(["app", "-orientation", "landscape", "-mode", "photo", "-screen", "record", "-recording", "on",
                                    "-state", "micDenied", "-freeSpaceMarginMB", "300", "-keepSweepClips", "on"])
        #expect(c == LaunchConfig(orientation: .landscape, mode: .photo, screen: .record, isRecording: true, simulatedState: .micDenied, freeSpaceMarginMB: 300, keepsSweepClips: true, isScripted: true))
        #expect(!LaunchConfig.parse(["app", "-freeSpaceMarginMB", "300"]).isScripted)
    }
    @Test func unknownValuesFallBack() { #expect(LaunchConfig.parse(["app", "-mode", "cinema", "-screen", "monitor"]) == LaunchConfig()) }
}
