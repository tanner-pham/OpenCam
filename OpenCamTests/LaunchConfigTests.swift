import Testing
@testable import OpenCam

@Suite struct LaunchConfigTests {
    @Test func parsesEveryFlag() {
        let c = LaunchConfig.parse(["app", "-orientation", "landscape", "-mode", "photo", "-screen", "record", "-recording", "on",
                                    "-state", "micDenied", "-freeSpaceMarginMB", "300", "-keepSweepClips", "on"])
        #expect(c == LaunchConfig(orientation: .landscape, mode: .photo, screen: .record, isRecording: true, simulatedState: .micDenied, freeSpaceMarginMB: 300, keepsSweepClips: true, isScripted: true))
        #expect(!LaunchConfig.parse(["app", "-freeSpaceMarginMB", "300"]).isScripted)
    }
    @Test func parsesLibraryAndEditorFlags() {
        let c = LaunchConfig.parse(["app", "-screen", "editor", "-editorGroup", "colour", "-seedSamples", "on", "-seedLook", "on", "-librarySelect", "on"])
        #expect(c.screen == .editor); #expect(c.editorGroup == .colour); #expect(c.seedsSamples); #expect(c.seedsLook); #expect(c.startsInSelectMode); #expect(c.isScripted)
        #expect(LaunchConfig.parse(["app", "-seedSamples", "on"]).isScripted)
        #expect(LaunchConfig.parse(["app", "-editorGroup", "masks", "-seedSamples", "off"]) == LaunchConfig())
    }
    @Test func parsesCameraLookFlag() {
        let c = LaunchConfig.parse(["app", "-cameraLook", "Warm fade", "-seedLook", "on"])
        #expect(c.cameraLookName == "Warm fade"); #expect(c.isScripted)
        #expect(LaunchConfig.parse(["app", "-cameraLook", "Warm fade"]).isScripted)   // the flag alone makes the launch scripted
        #expect(LaunchConfig.parse(["app"]).cameraLookName == nil)
    }
    @Test func unknownValuesFallBack() { #expect(LaunchConfig.parse(["app", "-mode", "cinema", "-screen", "monitor"]) == LaunchConfig()) }
    @Test func parsesSeedFormatsFlag() {
        #expect(LaunchConfig.parse(["app", "-seedFormats", "on"]).seedsFormats); #expect(LaunchConfig.parse(["app", "-seedFormats", "on"]).isScripted)
        #expect(!LaunchConfig.parse(["app"]).seedsFormats)
    }
}
