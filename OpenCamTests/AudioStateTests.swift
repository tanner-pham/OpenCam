import AVFAudio
import Testing
@testable import OpenCam

@Suite struct AudioStateTests {
    @Test func theBuiltInMicrophoneIsOneChipPerDataSource() {
        let state = AudioFixtures.live(AudioFixtures.usbRoute)
        #expect(state.sourceChips.map(\.id) == ["automatic", "mic#1", "mic#2", "mic#3", "usb"])
        #expect(state.sourceChips.map(\.detail) == ["Matches the camera", "Front", "Back", "Bottom", "USB Audio"])
        #expect(state.sourceChips.map(\.title) == ["Automatic", "Built-in", "Built-in", "Built-in", "USB"])
        #expect(state.selectedSourceID == "automatic")
        #expect(state.sourceChips.allSatisfy { $0.isAvailable })
    }

    @Test func portTypesMapToKinds() {
        let port = AVAudioSession.Port.self
        #expect(AudioPortKind(portType: port.builtInMic.rawValue) == .builtIn)
        #expect(AudioPortKind(portType: port.builtInSpeaker.rawValue) == .builtIn)
        #expect(AudioPortKind(portType: port.builtInReceiver.rawValue) == .builtIn)
        #expect(AudioPortKind(portType: port.headsetMic.rawValue) == .wired)
        #expect(AudioPortKind(portType: port.headphones.rawValue) == .wired)
        #expect(AudioPortKind(portType: port.usbAudio.rawValue) == .usb)
        #expect(AudioPortKind(portType: port.bluetoothA2DP.rawValue) == .bluetooth)
        #expect(AudioPortKind(portType: port.bluetoothHFP.rawValue) == .bluetooth)
        #expect(AudioPortKind(portType: port.bluetoothLE.rawValue) == .bluetooth)
        for other in [port.HDMI, port.airPlay, port.lineOut, port.lineIn, port.carAudio, port.virtual, port.continuityMicrophone] {
            #expect(AudioPortKind(portType: other.rawValue) == .other)
        }
        #expect(AudioPortKind(portType: "something new") == .other)
        #expect(AudioPortKind.other.title == "External")
        #expect(AudioPortKind.wired.title == "Wired")
    }

    @Test func aDataSourceWithNoOrientationKeepsTheSystemsName() {
        #expect(AudioDataSource(id: 1, name: "Studio capsule", orientation: nil).label == "Studio capsule")
        #expect(AudioDataSource(id: 2, name: "x", orientation: AVAudioSession.Orientation.top.rawValue).label == "Top")
        #expect(AudioDataSource(id: 3, name: "x", orientation: AVAudioSession.Orientation.left.rawValue).label == "Left")
        #expect(AudioDataSource(id: 4, name: "x", orientation: AVAudioSession.Orientation.right.rawValue).label == "Right")
        #expect(AudioDataSource(id: 5, name: "x", orientation: AVAudioSession.Orientation.front.rawValue).label == "Front")
    }

    @Test func withoutMicrophoneAccessEveryChipIsDimmed() {
        var state = AudioFixtures.live(AudioFixtures.wiredHeadphones)
        state.hasMicrophone = false
        #expect(state.sourceChips.allSatisfy { !$0.isAvailable })
        #expect(state.monitorChips.allSatisfy { !$0.isAvailable })
        #expect(state.sourceReason == "No microphone access.")
        #expect(state.monitorReason == "No microphone access.")
        state.select(chipID: "mic#2")
        state.setMonitor(true)
        #expect(state.plan == AudioPlan())
    }

    @Test func aChosenSourceSurvivesARouteChangeThatKeepsIt() {
        var state = AudioFixtures.live(AudioFixtures.speaker)
        state.select(chipID: "mic#2")
        #expect(state.selectedSourceID == "mic#2")
        #expect(state.routeChanged(to: AudioFixtures.wiredHeadphones) == nil)
        #expect(state.selectedSourceID == "mic#2")
        #expect(state.plan.pin == AudioFixtures.back)
    }

    @Test func aChosenSourceThatDisappearsFallsBackToAutomatic() {
        var state = AudioFixtures.live(AudioFixtures.usbRoute)
        state.select(chipID: "usb")
        #expect(state.plan.pin == AudioFixtures.usbPin)
        #expect(state.routeChanged(to: AudioFixtures.speaker) == "Microphone disconnected. Source is Automatic.")
        #expect(state.selectedSourceID == "automatic")
        #expect(state.plan == AudioPlan())
    }

    @Test func aDataSourceThatDisappearsFallsBackToo() {
        var state = AudioFixtures.live(AudioFixtures.speaker)
        state.select(chipID: "mic#3")
        let fewer = AudioInput(uid: "mic", kind: .builtIn, name: "iPhone Microphone", dataSources: [AudioFixtures.builtIn.dataSources[0]])
        #expect(state.routeChanged(to: AudioRoute(inputs: [fewer], outputs: [.builtIn])) == "Microphone disconnected. Source is Automatic.")
        #expect(state.selectedSourceID == "automatic")
    }

    @Test func monitoringIsOfferedOnlyWithHeadphones() {
        for outputs: [AudioPortKind] in [[.builtIn], [.builtIn], [], [.wired, .builtIn]] {
            var state = AudioFixtures.live(AudioRoute(inputs: [AudioFixtures.builtIn], outputs: outputs))
            let on = state.monitorChips[1]
            #expect(on.id == "on" && !on.isAvailable)
            #expect(on.reason == "Connect headphones to monitor.")
            #expect(state.monitorReason == "Connect headphones to monitor.")
            state.setMonitor(true)
            #expect(state.selectedMonitorID == "off")
            #expect(!state.plan.isMonitoring)
        }
        var wired = AudioFixtures.live(AudioFixtures.wiredHeadphones)
        #expect(wired.monitorChips[1].isAvailable)
        #expect(wired.monitorReason == nil)
        wired.setMonitor(true)
        #expect(wired.selectedMonitorID == "on")
        #expect(wired.plan.isMonitoring)
        var bluetooth = AudioFixtures.live(AudioFixtures.bluetoothHeadphones)
        #expect(bluetooth.monitorChips[1].isAvailable)
        #expect(bluetooth.monitorReason == "Bluetooth headphones add a delay.")
        bluetooth.select(chipID: "on")
        #expect(bluetooth.plan.isMonitoring)
    }

    @Test func monitoringTurnsItselfOffWhenHeadphonesGoAway() {
        var state = AudioFixtures.live(AudioFixtures.wiredHeadphones)
        state.setMonitor(true)
        #expect(state.routeChanged(to: AudioFixtures.speaker) == "Headphones disconnected. Monitoring is off.")
        #expect(state.selectedMonitorID == "off")
        #expect(!state.plan.isMonitoring)
        // It stays off when they return.
        #expect(state.routeChanged(to: AudioFixtures.wiredHeadphones) == nil)
        #expect(state.selectedMonitorID == "off")
        #expect(!state.plan.isMonitoring)
    }

    @Test func aHeadsetUnpluggedSaysTheMicrophoneWentAway() {
        var state = AudioFixtures.live(AudioFixtures.wiredHeadphones)
        state.select(chipID: "headset")
        state.setMonitor(true)
        #expect(state.routeChanged(to: AudioFixtures.speaker) == "Microphone disconnected. Source is Automatic.")
        #expect(state.selectedSourceID == "automatic")
        #expect(state.selectedMonitorID == "off")
    }

    @Test func aStoppedCameraPausesMonitoringAndKeepsTheChoice() {
        var state = AudioFixtures.live(AudioFixtures.wiredHeadphones)
        state.select(chipID: "mic#1")
        state.setMonitor(true)
        let running = state.plan
        #expect(running == AudioPlan(pin: AudioPin(portUID: "mic", dataSourceID: 1), captureConfiguresAudio: false, isMonitoring: true))
        state.isCameraLive = false
        #expect(state.routeChanged(to: AudioFixtures.wiredHeadphones) == nil)
        #expect(state.plan == AudioPlan(pin: AudioPin(portUID: "mic", dataSourceID: 1), captureConfiguresAudio: true, isMonitoring: false))
        #expect(state.selectedSourceID == "mic#1")
        #expect(state.selectedMonitorID == "on")
        // A route read while stopped that lists no inputs does not drop the choice.
        #expect(state.routeChanged(to: AudioRoute(inputs: [], outputs: [.wired])) == nil)
        #expect(state.routeChanged(to: AudioFixtures.wiredHeadphones) == nil)
        state.isCameraLive = true
        #expect(state.plan == running)
    }

    @Test func aRefusedPinFallsBackAndARefusedMonitorTurnsOff() {
        var state = AudioFixtures.live(AudioFixtures.wiredHeadphones)
        state.select(chipID: "headset")
        state.setMonitor(true)
        #expect(state.failed(.pinRefused(reason: "x")) == "That microphone could not be used. Source is Automatic.")
        #expect(state.selectedSourceID == "automatic")
        #expect(state.selectedMonitorID == "on")
        #expect(state.failed(.monitorRefused(reason: "x")) == "Monitoring could not start.")
        #expect(state.selectedMonitorID == "off")
        state.select(chipID: "headset")
        #expect(state.failed(.inputMissing(uid: "headset")) == "That microphone could not be used. Source is Automatic.")
        #expect(state.plan == AudioPlan())
    }

    @Test func anUnknownOrDimmedIdChangesNothing() {
        var state = AudioFixtures.live(AudioFixtures.speaker)
        let before = state
        state.select(chipID: "nothing")
        state.select(chipID: "on")
        #expect(state == before)
    }

    @Test func liveIsVideoOnARunningCamera() {
        #expect(AudioState.isLive(phase: .ready, mode: .video, isInterrupted: false))
        #expect(AudioState.isLive(phase: .simulator, mode: .video, isInterrupted: false))
        #expect(!AudioState.isLive(phase: .ready, mode: .photo, isInterrupted: false))
        #expect(!AudioState.isLive(phase: .ready, mode: .video, isInterrupted: true))
        #expect(!AudioState.isLive(phase: .scanning, mode: .video, isInterrupted: false))
        #expect(!AudioState.isLive(phase: .released, mode: .video, isInterrupted: false))
        #expect(!AudioState.isLive(phase: .failed("x"), mode: .video, isInterrupted: false))
        #expect(!AudioState.isLive(phase: .cameraDenied, mode: .video, isInterrupted: false))
    }

    @Test func noStringHasAnEmDash() {
        var state = AudioFixtures.live(AudioFixtures.bluetoothHeadphones)
        var texts: [String] = []
        func collect() {
            texts += (state.sourceChips + state.monitorChips).flatMap { [$0.title, $0.detail, $0.reason].compactMap { $0 } }
            texts += [state.sourceReason, state.monitorReason].compactMap { $0 }
        }
        collect()
        texts += [state.failed(.pinRefused(reason: "x")), state.failed(.monitorRefused(reason: "x"))]
        state.hasMicrophone = false
        collect()
        state.hasMicrophone = true
        _ = state.routeChanged(to: AudioFixtures.speaker)
        collect()
        texts += [AudioState.microphoneGoneNotice, AudioState.headphonesGoneNotice]
        for kind in [AudioPortKind.builtIn, .wired, .usb, .bluetooth, .other] { texts.append(kind.title) }
        #expect(texts.count > 10)
        #expect(texts.allSatisfy { !$0.contains("\u{2014}") })
    }
}
