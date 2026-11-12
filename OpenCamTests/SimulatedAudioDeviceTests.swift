import Testing
@testable import OpenCam

@Suite struct SimulatedAudioDeviceTests {
    // These live here, not in LaunchConfigTests, which another branch is editing.
    @Test func theTwoFlagsParseAndLeaveTheLaunchUnscripted() {
        let both = LaunchConfig.parse(["app", "-wiredMic", "on", "-headphones", "on"])
        #expect(both.hasWiredMicrophone); #expect(both.hasHeadphones); #expect(!both.isScripted)
        let none = LaunchConfig.parse(["app"])
        #expect(!none.hasWiredMicrophone); #expect(!none.hasHeadphones)
        #expect(LaunchConfig.parse(["app", "-wiredMic", "off", "-headphones", "yes"]) == LaunchConfig())
    }

    @Test func theFourRoutes() async {
        func route(_ args: [String]) async -> AudioRoute {
            await SimulatedAudioDevice(config: LaunchConfig.parse(["app"] + args)).route()
        }
        let plain = await route([])
        #expect(plain.inputs.map(\.kind) == [.builtIn])
        #expect(plain.inputs[0].dataSources.map(\.label) == ["Front", "Back", "Bottom"])
        #expect(plain.outputs == [.builtIn]); #expect(plain.headphones == nil)
        let headset = await route(["-wiredMic", "on"])
        #expect(headset.inputs.map(\.kind) == [.builtIn, .wired]); #expect(headset.headphones == nil)
        let phones = await route(["-headphones", "on"])
        #expect(phones.inputs.map(\.kind) == [.builtIn]); #expect(phones.headphones == .wired)
        let both = await route(["-wiredMic", "on", "-headphones", "on"])
        #expect(both.inputs.map(\.kind) == [.builtIn, .wired]); #expect(both.headphones == .wired)
    }

    @Test func applyingChangesNothing() async throws {
        let device = SimulatedAudioDevice(config: LaunchConfig())
        let before = await device.route()
        try await device.apply(AudioPlan(pin: AudioFixtures.usbPin, captureConfiguresAudio: false, isMonitoring: true))
        #expect(await device.route() == before)
    }
}
