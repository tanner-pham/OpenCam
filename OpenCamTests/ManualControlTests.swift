import Foundation
import Testing
@testable import OpenCam

/// The model's manual state: opening, moving, sending to the session, and what the readouts show.
@MainActor @Suite struct ManualControlTests {
    static let ranges = ManualRanges(shutterSeconds: (1.0 / 8000)...(1.0 / 3), iso: 25...3200, bias: -2...2, hasWhiteBalance: true, hasFocus: true)
    static let live = LiveReadouts(iso: 400, shutterSeconds: 1.0 / 60, kelvin: 5000, tint: 12, exposureBias: 0, lensPosition: 0.5)

    struct Rig {
        let model: CameraModel
        let fake: FakeSessionConfigurator
        let defaults: UserDefaults
    }

    func rig() async throws -> Rig {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        await fake.setRanges(Self.ranges)
        await fake.setReadouts(Self.live)
        let source = CapabilitySource(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                                      documentsDirectory: nil, discoverLenses: { [] }, scan: { _ in [] })
        let defaults = try Fixture.freshDefaults()
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: defaults,
                                capabilitySource: source, captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.mode = .photo
        model.phase = .ready
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        await model.refreshReadouts(from: fake)
        return Rig(model: model, fake: fake, defaults: defaults)
    }

    func simulator(_ args: [String] = ["app", "-mode", "photo"]) throws -> CameraModel {
        CameraModel(config: .parse(args), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
    }

    func until(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    @Test func tappingAReadoutOpensItsSliderAndAnotherSwitches() async throws {
        let rig = try await rig()
        rig.model.toggleControl(.iso)
        #expect(rig.model.openControl == .iso)
        #expect(rig.model.openSlider?.control == .iso)
        #expect(rig.model.readout(for: .iso).isOpen)
        rig.model.toggleControl(.shutter)
        #expect(rig.model.openControl == .shutter)
        #expect(!rig.model.readout(for: .iso).isOpen)
        rig.model.toggleControl(.shutter)
        #expect(rig.model.openControl == nil)
        #expect(rig.model.openSlider == nil)
        #expect(await rig.fake.manualApplies.isEmpty)
        #expect(rig.model.manual == .automatic)
    }

    @Test func theFirstMoveLocksBothAndTheReadoutsShowIt() async throws {
        let rig = try await rig()
        let scale = try #require(rig.model.scale(for: .shutter))
        let start = scale.step(nearest: 1.0 / 60)
        rig.model.setControl(.shutter, step: start + 1)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.exposure == .manual(shutterSeconds: scale.values[start + 1], iso: nil))
        #expect(rig.model.readout(for: .shutter).isSet)
        #expect(rig.model.readout(for: .iso).isSet)
        #expect(rig.model.readout(for: .shutter).text == ReadoutFormatter.shutter(scale.values[start + 1]))
        #expect(rig.model.readout(for: .iso).text == "400")
        #expect(!rig.model.readout(for: .temperature).isSet)
        let applies = await rig.fake.manualApplies
        #expect(applies.count == 1)
        #expect(applies.last?.settings == rig.model.manual)
    }

    @Test func autoReturnsBothAndIsSent() async throws {
        let rig = try await rig()
        rig.model.setControl(.iso, step: 4)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.readout(for: .shutter).isSet)
        rig.model.setAutomatic(.iso)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.exposure == .automatic)
        #expect(!rig.model.readout(for: .shutter).isSet)
        #expect(!rig.model.readout(for: .iso).isSet)
        #expect(rig.model.readout(for: .iso).text == "400")
        let applies = await rig.fake.manualApplies
        #expect(applies.count == 2)
        #expect(applies.last?.settings.exposure == .automatic)
    }

    @Test func evCannotBeOpenedOrMovedWhileExposureIsManual() async throws {
        let rig = try await rig()
        #expect(rig.model.readout(for: .bias).isAvailable)
        rig.model.setControl(.iso, step: 4)
        await rig.model.manualApplyTask?.value
        let state = rig.model.readout(for: .bias)
        #expect(state.text == "--")
        #expect(!state.isAvailable)
        rig.model.toggleControl(.bias)
        #expect(rig.model.openControl == nil)
        rig.model.setControl(.bias, step: 3)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.bias == nil)
        #expect(await rig.fake.manualApplies.count == 1)
    }

    @Test func whiteBalanceTakesTheOtherValueFromTheLiveReadout() async throws {
        let rig = try await rig()
        let scale = try #require(rig.model.scale(for: .temperature))
        rig.model.setControl(.temperature, step: 10)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.whiteBalance == .manual(kelvin: Float(scale.values[10]), tint: 12))
        let tint = try #require(rig.model.scale(for: .tint))
        rig.model.setControl(.tint, step: 40)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.whiteBalance == .manual(kelvin: Float(scale.values[10]), tint: Float(tint.values[40])))
    }

    /// The fake records an apply before it waits and, with ranges set, clamps: one apply is in flight when the 30 moves
    /// arrive, so the 30 replace each other and one more apply carries the last. Two in all.
    @Test func aBurstWhileOneApplyRunsSendsOnlyTheLatest() async throws {
        let rig = try await rig()
        await rig.fake.holdManual()
        rig.model.setControl(.iso, step: 5)
        #expect(await until { await rig.fake.manualApplies.count == 1 })
        for index in 0..<30 { rig.model.setControl(.iso, step: 6 + index % 10) }
        #expect(await rig.fake.manualApplies.count == 1)
        await rig.fake.resumeManual()
        await rig.model.manualApplyTask?.value
        let applies = await rig.fake.manualApplies
        #expect(applies.count == 2)
        #expect(applies.last?.settings == rig.model.manual)
        #expect(applies.first?.settings != applies.last?.settings)
    }

    @Test func aFailedApplyReturnsToWhatTheCameraHasWithTheNotice() async throws {
        let rig = try await rig()
        await rig.fake.setManualError(.lockFailed(reason: "busy"))
        rig.model.setControl(.focus, step: 30)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual == .automatic)
        #expect(rig.model.notice == "That setting could not be applied.")
        #expect(rig.model.noticeSource == .control)
        await rig.fake.setManualError(nil)
        rig.model.setControl(.focus, step: 30)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.focus != nil)
        #expect(rig.model.notice == nil)
    }

    @Test func noCameraReturnsQuietly() async throws {
        let rig = try await rig()
        await rig.fake.setManualError(.noCamera)
        rig.model.setControl(.focus, step: 30)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual == .automatic)
        #expect(rig.model.notice == nil)
    }

    @Test func aClampedValueIsAdopted() async throws {
        let rig = try await rig()
        var narrow = Self.ranges
        narrow.iso = 25...200
        await rig.fake.setRanges(narrow)
        let scale = try #require(rig.model.scale(for: .iso))
        rig.model.setControl(.iso, step: scale.values.count - 1)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.exposure == .manual(shutterSeconds: nil, iso: 200))
        #expect(rig.model.readout(for: .iso).text == "200")
    }

    @Test func eachDetentCountsOneHaptic() async throws {
        let rig = try await rig()
        let iso = try #require(rig.model.scale(for: .iso))
        let start = iso.step(nearest: 400)
        #expect(rig.model.feedback.controlSteps == 0)
        for offset in 1...3 { rig.model.setControl(.iso, step: start + offset) }
        #expect(rig.model.feedback.controlSteps == 3)
        rig.model.setControl(.iso, step: start + 3)
        #expect(rig.model.feedback.controlSteps == 3)
        let tint = try #require(rig.model.scale(for: .tint))
        let tintStart = tint.step(nearest: 12)
        for offset in 1...4 { rig.model.setControl(.tint, step: tintStart + offset) }
        #expect(rig.model.feedback.controlSteps == 3)
        await rig.model.manualApplyTask?.value
    }

    @Test func aControlChangeNeverReconfiguresBlursOrSaves() async throws {
        let rig = try await rig()
        let saved = SavedSelections.load(from: rig.defaults)
        rig.model.toggleControl(.iso)
        rig.model.setControl(.iso, step: 6)
        rig.model.setControl(.temperature, step: 20)
        rig.model.setAutomatic(.iso)
        rig.model.setControl(.focus, step: 50)
        #expect(!rig.model.isViewfinderChanging)
        await rig.model.manualApplyTask?.value
        #expect(!rig.model.isViewfinderChanging)
        #expect(await rig.fake.applied.isEmpty)
        #expect(await rig.fake.calls.allSatisfy { $0 == "manual" || $0 == "manual done" })
        #expect(SavedSelections.load(from: rig.defaults) == saved)
        let fresh = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: rig.defaults)
        #expect(fresh.manual == .automatic)
        #expect(fresh.openControl == nil)
    }

    @Test func theSimulatorHasRangesAndValues() throws {
        for mode in ["photo", "video"] {
            let model = try simulator(["app", "-mode", mode])
            for control in ManualControl.allCases {
                #expect(model.scale(for: control) != nil)
                #expect(model.readout(for: control).text != "--")
                #expect(model.readout(for: control).isAvailable)
            }
        }
        let model = try simulator()
        let before = model.readout(for: .iso).text
        let scale = try #require(model.scale(for: .iso))
        model.setControl(.iso, step: scale.step(nearest: 100) + 5)
        #expect(model.readout(for: .iso).text != before)
        #expect(model.readout(for: .iso).isSet)
        model.setAutomatic(.iso)
        #expect(model.readout(for: .iso).text == before)
        #expect(!model.readout(for: .iso).isSet)
        let scanning = try simulator(["app", "-state", "scanning"])
        for control in ManualControl.allCases {
            #expect(scanning.readout(for: control).text == "--")
            #expect(!scanning.readout(for: control).isAvailable)
            scanning.toggleControl(control)
        }
        #expect(scanning.openControl == nil)
    }

    @Test func aScriptedLaunchOpensItsControlInTheSimulatorOnly() throws {
        #expect(try simulator(["app", "-mode", "photo", "-control", "wb"]).openControl == .temperature)
        #expect(try simulator(["app", "-state", "scanning", "-control", "wb"]).openControl == nil)
        let device = CameraModel(config: .parse(["app", "-control", "wb"]), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        #expect(device.openControl == nil)
    }
}
