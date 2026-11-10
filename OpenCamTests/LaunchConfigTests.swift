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
    @Test func unknownValuesFallBack() { #expect(LaunchConfig.parse(["app", "-mode", "cinema", "-screen", "monitor"]) == LaunchConfig()) }
}
