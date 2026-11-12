import Testing
@testable import OpenCam

@Suite struct AudioModelTests {
    private func started(_ route: AudioRoute, isLive: Bool = true) async -> (AudioModel, FakeAudioDevice) {
        let device = FakeAudioDevice(route: route)
        let model = AudioModel(device: device)
        model.setCamera(isLive: isLive, hasMicrophone: true)
        await model.settle()
        return (model, device)
    }

    @Test func aTapSendsThePlan() async {
        let (model, device) = await started(AudioFixtures.usbRoute)
        model.select(chipID: "usb")
        await model.settle()
        #expect(await device.plans.last == AudioPlan(pin: AudioFixtures.usbPin, captureConfiguresAudio: false))
        #expect(model.state.selectedSourceID == "usb")
        #expect(model.notice == nil)
    }

    @Test func nothingChosenSendsOnlyTheDefaultPlan() async {
        let (model, device) = await started(AudioFixtures.speaker, isLive: false)
        model.setCamera(isLive: true, hasMicrophone: true)
        await model.settle()
        await device.setRoute(AudioFixtures.wiredHeadphones)
        model.setCamera(isLive: true, hasMicrophone: true)
        await model.settle()
        model.setCamera(isLive: false, hasMicrophone: true)
        await model.settle()
        await device.setRoute(AudioFixtures.usbRoute)
        model.setCamera(isLive: true, hasMicrophone: false)
        await model.settle()
        model.select(chipID: "automatic")
        model.setMonitor(false)
        await model.settle()
        let plans = await device.plans
        #expect(plans.count >= 6)
        #expect(plans.allSatisfy { $0 == AudioPlan() })
    }

    @Test func aRouteChangeDropsTheMissingSourceAndSaysSo() async {
        let (model, device) = await started(AudioFixtures.usbRoute)
        model.select(chipID: "usb")
        await model.settle()
        await device.setRoute(AudioFixtures.speaker)
        model.setCamera(isLive: true, hasMicrophone: true)
        await model.settle()
        #expect(model.state.selectedSourceID == "automatic")
        #expect(model.notice == "Microphone disconnected. Source is Automatic.")
        #expect(await device.plans.last == AudioPlan())
    }

    @Test func aRefusedPinFallsBackOnce() async {
        let (model, device) = await started(AudioFixtures.usbRoute)
        await device.setRefusesPins(true)
        let before = await device.plans.count
        model.select(chipID: "usb")
        await model.settle()
        let plans = await device.plans
        #expect(plans.count == before + 2)
        #expect(plans[before] == AudioPlan(pin: AudioFixtures.usbPin, captureConfiguresAudio: false))
        #expect(plans.last == AudioPlan())
        #expect(model.state.selectedSourceID == "automatic")
        #expect(model.notice == "That microphone could not be used. Source is Automatic.")
    }

    @Test func aMonitorThatCannotStartTurnsOff() async {
        let (model, device) = await started(AudioFixtures.wiredHeadphones)
        await device.setRefusesMonitors(true)
        model.setMonitor(true)
        await model.settle()
        #expect(model.state.selectedMonitorID == "off")
        #expect(model.notice == "Monitoring could not start.")
        #expect(await device.plans.last == AudioPlan())
    }

    @Test func unpluggingHeadphonesStopsMonitoring() async {
        let (model, device) = await started(AudioFixtures.wiredHeadphones)
        model.setMonitor(true)
        await model.settle()
        #expect(await device.plans.last == AudioPlan(isMonitoring: true))
        await device.setRoute(AudioFixtures.speaker)
        model.setCamera(isLive: true, hasMicrophone: true)
        await model.settle()
        #expect(model.state.selectedMonitorID == "off")
        #expect(model.notice == "Headphones disconnected. Monitoring is off.")
        #expect(await device.plans.last == AudioPlan())
    }

    @Test func aNewChoiceClearsTheNotice() async {
        let (model, device) = await started(AudioFixtures.usbRoute)
        model.select(chipID: "usb")
        await model.settle()
        await device.setRoute(AudioFixtures.speaker)
        model.setCamera(isLive: true, hasMicrophone: true)
        await model.settle()
        #expect(model.notice != nil)
        model.select(chipID: "mic#1")
        #expect(model.notice == nil)
        await model.settle()
        #expect(model.notice == nil)
    }

    @Test func deviceChangesReachTheModel() async {
        let (model, device) = await started(AudioFixtures.speaker)
        let following = Task { await model.run() }
        await device.setRoute(AudioFixtures.wiredHeadphones)
        await device.send(.routeChanged)
        #expect(await eventually { model.state.route == AudioFixtures.wiredHeadphones })
        model.setMonitor(true)
        await model.settle()
        await device.send(.failed(.monitorRefused(reason: "engine")))
        #expect(await eventually { model.notice == "Monitoring could not start." })
        await model.settle()
        #expect(model.state.selectedMonitorID == "off")
        #expect(await device.plans.last == AudioPlan())
        following.cancel()
    }
}
