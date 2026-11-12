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
    @Test func parsesControlFlag() {
        let c = LaunchConfig.parse(["app", "-control", "wb"])
        #expect(c.openControl == .temperature); #expect(c.isScripted)
        #expect(LaunchConfig.parse(["app", "-control", "shutter"]).openControl == .shutter)
        #expect(LaunchConfig.parse(["app", "-control", "ev"]).openControl == .bias)
        #expect(LaunchConfig.parse(["app", "-control", "aperture"]) == LaunchConfig())
        #expect(LaunchConfig.parse(["app"]).openControl == nil)
    }
    @Test func parsesSliderPlacementFlag() {
        let c = LaunchConfig.parse(["app", "-sliderPlacement", "picture"])
        #expect(c.forcesPictureSlider); #expect(c.isScripted)
        #expect(!LaunchConfig.parse(["app"]).forcesPictureSlider)
        #expect(LaunchConfig.parse(["app", "-sliderPlacement", "strip"]) == LaunchConfig())
    }
    @Test func unknownValuesFallBack() { #expect(LaunchConfig.parse(["app", "-mode", "cinema", "-screen", "monitor"]) == LaunchConfig()) }
}
