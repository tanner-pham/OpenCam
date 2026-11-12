import Foundation
import Testing
@testable import OpenCam

/// What closes the open slider and what returns the controls to automatic, and how that stays in step with the camera.
@MainActor @Suite struct ManualLifecycleTests {
    static let ranges = ManualRanges(shutterSeconds: (1.0 / 8000)...(1.0 / 3), iso: 25...3200, bias: -2...2, hasWhiteBalance: true, hasFocus: true)
    static let live = LiveReadouts(iso: 400, shutterSeconds: 1.0 / 60, kelvin: 5000, tint: 12, exposureBias: 0, lensPosition: 0.5)
    static let otherRecord = RecordSelection(family: .proRes, quality: "422 HQ", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)

    struct Rig {
        let model: CameraModel
        let fake: FakeSessionConfigurator
    }

    func rig(mode: CaptureMode = .photo) async throws -> Rig {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        await fake.setRanges(Self.ranges)
        await fake.setReadouts(Self.live)
        let source = CapabilitySource(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                                      documentsDirectory: nil, discoverLenses: { [] }, scan: { _ in [] })
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source, captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.mode = mode
        model.phase = .ready
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        await model.refreshReadouts(from: fake)
        return Rig(model: model, fake: fake)
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

    /// ISO and temperature set by hand, the ISO slider open, every apply finished.
    func setByHand(_ rig: Rig) async throws {
        rig.model.toggleControl(.iso)
        rig.model.setControl(.iso, step: 5)
        rig.model.setControl(.temperature, step: 10)
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual != .automatic)
        #expect(rig.model.openControl == .iso)
    }

    func expectAutomaticAndClosed(_ model: CameraModel, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(model.manual == .automatic, sourceLocation: sourceLocation)
        #expect(model.openControl == nil, sourceLocation: sourceLocation)
        #expect(model.appliedManual == .automatic, sourceLocation: sourceLocation)
    }

    // MARK: Recording

    @Test func recordingKeepsTheSliderAndItsValues() async throws {
        let rig = try await rig()
        rig.model.toggleControl(.iso)
        rig.model.isRecording = true
        rig.model.setControl(.iso, step: 6)
        await rig.model.manualApplyTask?.value
        // The move reaches the camera as an apply while recording, and nothing configures it.
        let applies = await rig.fake.manualApplies
        #expect(applies.count == 1)
        #expect(applies.first?.settings == rig.model.manual)
        #expect(rig.model.manual != .automatic)
        #expect(!(await rig.fake.calls.contains("configure")))
        #expect(rig.model.openControl == .iso)
        let held = rig.model.manual
        let heldControl = rig.model.openControl
        let configures = await rig.fake.applied.count
        // The stop queues no configure and changes neither the slider nor the values.
        rig.model.isRecording = false
        #expect(rig.model.enqueueConfigure() == nil)
        #expect(!rig.model.isConfigurePending)
        await rig.model.waitForQueuedConfigures()
        #expect(!(await rig.fake.calls.contains("configure")))
        #expect(await rig.fake.applied.count == configures)
        #expect(await rig.fake.manualApplies.count == 1)
        #expect(rig.model.openControl == heldControl)
        #expect(rig.model.manual == held)
    }

    // MARK: A configure is queued

    @Test func aCameraChangeReturnsEverythingToAutomaticAndClosesTheSlider() async throws {
        let rig = try await rig()
        let changes: [(String, () -> Void)] = [
            ("lens", { rig.model.selectLens("ultraWide") }),
            ("mode", { rig.model.mode = .video }),
            ("record selection", { rig.model.record = Self.otherRecord }),
        ]
        for (name, change) in changes {
            await rig.model.refreshReadouts(from: rig.fake)
            try await setByHand(rig)
            let before = await rig.fake.manualApplies.count
            let configures = await rig.fake.applied.count
            change()
            await rig.model.waitForQueuedConfigures()
            #expect(await rig.fake.applied.count == configures + 1, "\(name) configures")
            expectAutomaticAndClosed(rig.model)
            // Nothing manual waits behind the configure: the only apply after the change's reset is the automatic one.
            let after = await rig.fake.manualApplies.dropFirst(before).map(\.settings)
            #expect(after == [ManualSettings.automatic], "\(name) sends only automatic")
            #expect(rig.model.manualApplies.isIdle)
        }
    }

    @Test func aSliderMovedWhileTheCameraChangesIsNotSent() async throws {
        let rig = try await rig()
        await rig.fake.holdConfigures()
        rig.model.selectLens("ultraWide")
        // The fake still answers with the old camera's ranges.
        await rig.model.refreshReadouts(from: rig.fake)
        #expect(rig.model.manualRanges == nil)
        rig.model.toggleControl(.iso)
        rig.model.setControl(.iso, step: 6)
        rig.model.setAutomatic(.iso)
        #expect(rig.model.openControl == nil)
        #expect(rig.model.manual == .automatic)
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
        await rig.model.manualApplyTask?.value
        #expect(await rig.fake.manualApplies.isEmpty)
    }

    /// Protection (c): with the old camera's ranges handed to the model while a configure waits, the three entry points still refuse.
    @Test func theThreeEntryPointsAreRefusedWhileAConfigureIsPending() async throws {
        let rig = try await rig()
        await rig.fake.holdConfigures()
        rig.model.selectLens("ultraWide")
        #expect(rig.model.isConfigurePending)
        rig.model.adoptRanges(Self.ranges)
        #expect(rig.model.scale(for: .iso) != nil)
        rig.model.toggleControl(.iso)
        #expect(rig.model.openControl == nil)
        rig.model.setControl(.iso, step: 6)
        #expect(rig.model.manual == .automatic)
        rig.model.manual = ManualSettings(exposure: .manual(shutterSeconds: 0.01, iso: 100))
        rig.model.setAutomatic(.iso)
        #expect(rig.model.manual.exposure == .manual(shutterSeconds: 0.01, iso: 100))
        rig.model.manual = .automatic
        #expect(!rig.model.readout(for: .iso).isAvailable)
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.manualApplies.isEmpty)
    }

    /// Protection (a), part one: a queued configure bumps the generation an apply in flight was started under.
    @Test func aQueuedConfigureBumpsTheManualGeneration() async throws {
        let rig = try await rig()
        await rig.fake.holdConfigures()
        let generation = rig.model.manualGeneration
        rig.model.selectLens("ultraWide")
        #expect(rig.model.manualGeneration > generation)
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
    }

    /// Protection (a), part two: the generation check alone keeps a clamped result out of the model.
    @Test func aStaleClampedResultIsNotAdopted() async throws {
        let rig = try await rig()
        var narrow = Self.ranges
        narrow.iso = 25...200
        await rig.fake.setRanges(narrow)
        await rig.model.refreshReadouts(from: rig.fake)
        await rig.fake.holdManual()
        let top = try #require(rig.model.scale(for: .iso)).values.count - 1
        rig.model.setControl(.iso, step: top)
        #expect(await until { await rig.fake.manualApplies.count == 1 })
        let sent = rig.model.manual
        rig.model.manualGeneration += 1
        await rig.fake.resumeManual()
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual == sent)
        #expect(rig.model.appliedManual == .automatic)
    }

    /// Protection (b): the configure does not run until the apply in flight has finished.
    @Test func theConfigureWaitsForTheApplyInFlight() async throws {
        let rig = try await rig()
        await rig.fake.holdManual()
        rig.model.setControl(.iso, step: 6)
        #expect(await until { await rig.fake.manualApplies.count == 1 })
        rig.model.selectLens("ultraWide")
        try await Task.sleep(for: .milliseconds(150))
        #expect(await rig.fake.calls == ["manual"])
        await rig.fake.resumeManual()
        await rig.model.waitForQueuedConfigures()
        let calls = await rig.fake.calls
        let done = try #require(calls.firstIndex(of: "manual done"))
        let configure = try #require(calls.firstIndex(of: "configure"))
        #expect(configure > done)
        // The configure also comes after the reset's own apply, which is the last one before it.
        #expect(calls == ["manual", "manual done", "manual", "manual done", "configure"])
        #expect(await rig.fake.manualApplies.last?.settings == .automatic)
    }

    // MARK: The slider closes

    @Test func theSliderClosesWheneverItsControlCannotBeAdjusted() async throws {
        // A stopped camera.
        let stopped = try await rig()
        stopped.model.toggleControl(.iso)
        stopped.model.phase = .failed("The camera stopped.")
        #expect(stopped.model.openControl == nil)
        // A control that lost its range.
        let lost = try await rig()
        lost.model.toggleControl(.focus)
        #expect(lost.model.openControl == .focus)
        var noFocus = Self.ranges
        noFocus.hasFocus = false
        await lost.fake.setRanges(noFocus)
        await lost.model.refreshReadouts(from: lost.fake)
        #expect(lost.model.openControl == nil)
        // The Library.
        let library = try await rig()
        library.model.toggleControl(.iso)
        library.model.openLibrary()
        #expect(library.model.openControl == nil)
        // A sheet.
        let sheet = try await rig()
        sheet.model.toggleControl(.iso)
        sheet.model.openRecordSettings()
        #expect(sheet.model.sheet == .record)
        #expect(sheet.model.openControl == nil)
        let sweepSheet = try await rig(mode: .video)
        sweepSheet.model.toggleControl(.iso)
        sweepSheet.model.openSweep()
        #expect(sweepSheet.model.sheet == .sweep)
        #expect(sweepSheet.model.openControl == nil)
        // The Camera Control going full screen.
        let fullscreen = try await rig()
        fullscreen.model.toggleControl(.iso)
        fullscreen.model.apply(.systemControlsFullscreen)
        #expect(fullscreen.model.openControl == nil)
        // An interruption, at the next poll.
        let interrupted = try await rig()
        interrupted.model.toggleControl(.iso)
        interrupted.model.apply(.interrupted(.cameraInUse))
        await interrupted.fake.setRanges(nil)
        await interrupted.model.refreshReadouts(from: interrupted.fake)
        #expect(interrupted.model.openControl == nil)
    }

    @Test func theSimulatorClosesTheSliderForTheSameEvents() async throws {
        let sheet = try simulator()
        sheet.toggleControl(.iso)
        #expect(sheet.openControl == .iso)
        sheet.openRecordSettings()
        #expect(sheet.openControl == nil)
        let sweepSheet = try simulator(["app", "-mode", "video"])
        sweepSheet.toggleControl(.iso)
        sweepSheet.openSweep()
        #expect(sweepSheet.openControl == nil)
        let library = try simulator()
        library.toggleControl(.iso)
        library.setControl(.iso, step: 4)
        library.openLibrary()
        #expect(library.openControl == nil)
        #expect(library.manual == .automatic)
        let fullscreen = try simulator()
        fullscreen.toggleControl(.iso)
        fullscreen.setControl(.iso, step: 4)
        let held = fullscreen.manual
        fullscreen.apply(.systemControlsFullscreen)
        #expect(fullscreen.openControl == nil)
        #expect(fullscreen.manual == held)
    }

    @Test func recordSettingsAndTheSweepSheetKeepTheValues() async throws {
        let rig = try await rig(mode: .video)
        try await setByHand(rig)
        let held = rig.model.manual
        rig.model.openRecordSettings()
        #expect(rig.model.openControl == nil)
        #expect(rig.model.manual == held)
        rig.model.sheet = nil
        rig.model.openSweep()
        #expect(rig.model.manual == held)
        #expect(rig.model.appliedManual == held)
        #expect(await rig.fake.manualApplies.count == 2)
    }

    @Test func aSweepStartReturnsTheControlsToAutomatic() async throws {
        let model = try simulator(["app", "-mode", "video"])
        model.toggleControl(.iso)
        model.setControl(.iso, step: 4)
        #expect(model.manual != .automatic)
        let store = try CaptureStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let lens = Lens(id: "wide", kind: .wide, deviceUniqueID: "W", zoomFactor: 1, label: "1x")
        let option = VideoOption(lensID: "wide", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high),
                                 resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
        let driver = FakeSweepDriver(directory: store.directory, failingCodecs: [])
        var seen: (ManualSettings, ManualControl?)?
        driver.onClipStarted = { seen = (model.manual, model.openControl) }
        let sweep = FormatSweep(driver: driver, store: store, lens: lens, options: [option], keepsClips: false, clipDuration: .milliseconds(10))
        driver.sweep = sweep
        await model.runSweep(sweep, lensID: lens.id)
        #expect(seen?.0 == .automatic)
        #expect(seen?.1 == nil)
        #expect(model.openControl == nil)
    }

    // MARK: Leaving ready

    @Test func aStoppedCameraComesBackAutomatic() async throws {
        let rig = try await rig()
        try await setByHand(rig)
        rig.model.phase = .failed("The camera stopped.")
        expectAutomaticAndClosed(rig.model)
        await rig.model.manualApplyTask?.value
        #expect(await rig.fake.manualApplies.last?.settings == .automatic)
        rig.model.phase = .ready
        await rig.model.refreshReadouts(from: rig.fake)
        #expect(rig.model.manual == .automatic)
        #expect(rig.model.manualRanges != nil)
        #expect(!rig.model.readout(for: .iso).isSet)
    }

    @Test func settingTheSamePhaseAgainChangesNothing() async throws {
        let rig = try await rig()
        try await setByHand(rig)
        let held = rig.model.manual
        let applies = await rig.fake.manualApplies.count
        let generation = rig.model.manualGeneration
        rig.model.phase = .ready
        #expect(rig.model.openControl == .iso)
        #expect(rig.model.manual == held)
        #expect(rig.model.manualGeneration == generation)
        #expect(await rig.fake.manualApplies.count == applies)
    }

    @Test func buildingTheModelStartsNothing() throws {
        let denied = try simulator(["app", "-state", "cameraDenied"])
        #expect(denied.manualApplyTask == nil)
        #expect(denied.manualApplies.isIdle)
        #expect(denied.manual == .automatic)
        #expect(denied.openControl == nil)
    }

    @Test func anInterruptionKeepsTheValuesAndAppliesThemAgain() async throws {
        let rig = try await rig()
        try await setByHand(rig)
        let held = rig.model.manual
        rig.model.apply(.interrupted(.cameraInUse))
        await rig.fake.setRanges(nil)
        await rig.model.refreshReadouts(from: rig.fake)
        #expect(rig.model.openControl == nil)
        #expect(rig.model.manual == held)
        let before = await rig.fake.manualApplies.count
        await rig.fake.setRanges(Self.ranges)
        rig.model.apply(.interruptionEnded)
        await rig.model.manualApplyTask?.value
        let applies = await rig.fake.manualApplies
        #expect(applies.count == before + 1)
        #expect(applies.last?.reapplyingAll == true)
        #expect(applies.last?.settings == rig.model.manual)
        #expect(rig.model.manual == held)
    }

    @Test func aFailedResendDoesNotCarryOverToANewCamera() async throws {
        let rig = try await rig()
        try await setByHand(rig)
        rig.model.apply(.interrupted(.cameraInUse))
        await rig.fake.holdManual()
        rig.model.apply(.interruptionEnded)
        let before = await rig.fake.manualApplies.count
        #expect(await until { await rig.fake.manualApplies.count == before + 1 })
        #expect(await rig.fake.manualApplies.last?.reapplyingAll == true)
        // The camera changes while the re-send is in flight, and the re-send fails.
        rig.model.selectLens("ultraWide")
        await rig.fake.setManualError(.lockFailed(reason: "busy"))
        await rig.fake.resumeManual()
        await rig.model.manualApplyTask?.value
        await rig.model.waitForQueuedConfigures()
        #expect(!rig.model.reappliesAllManual)
        await rig.fake.setManualError(nil)
        rig.model.setControl(.focus, step: 30)
        await rig.model.manualApplyTask?.value
        #expect(await rig.fake.manualApplies.last?.reapplyingAll == false)
    }

    @Test func anInterruptionEndingWithNothingSetSendsNothing() async throws {
        let rig = try await rig()
        rig.model.apply(.interrupted(.background))
        rig.model.apply(.interruptionEnded)
        await rig.model.manualApplyTask?.value
        #expect(await rig.fake.manualApplies.isEmpty)
    }

    // MARK: The Library

    /// Drives: values set and applied; `openLibrary()` (the phase leaves ready, the reset's automatic apply starts); the Library
    /// is closed before the handoff's release step runs, so the session never let go; `closeLibrary()`. The fake is still
    /// running and holds its camera, so it accepts the reset's apply; had the release run first the fake would refuse it
    /// with `.noCamera` and its applied settings would stay the old manual ones.
    @Test func aLibraryClosedBeforeTheReleaseRanLeavesTheCameraAutomatic() async throws {
        let rig = try await rig()
        try await setByHand(rig)
        let held = rig.model.manual
        #expect(await rig.fake.appliedManual == held)
        rig.model.openLibrary()
        #expect(rig.model.phase == .released)
        expectAutomaticAndClosed(rig.model)
        rig.model.isLibraryPresented = false
        await rig.model.closeLibrary()
        await rig.model.manualApplyTask?.value
        #expect(rig.model.phase == .ready)
        #expect(!(await rig.fake.calls.contains("release")))
        #expect(await rig.fake.manualApplies.last?.settings == .automatic)
        #expect(await rig.fake.appliedManual == .automatic)
        #expect(rig.model.manual == .automatic)
    }

    // MARK: Dimming

    @Test func readoutsDoNotDimWhileTheCameraChanges() async throws {
        let rig = try await rig()
        #expect(rig.model.readout(for: .iso).isAvailable)
        await rig.fake.holdConfigures()
        rig.model.selectLens("ultraWide")
        #expect(rig.model.manualRanges == nil)
        for control in ManualControl.allCases {
            let state = rig.model.readout(for: control)
            #expect(!state.isDimmed, "\(control)")
            #expect(!state.isAvailable, "\(control)")
        }
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
        for control in ManualControl.allCases {
            #expect(rig.model.readout(for: control).isAvailable, "\(control)")
        }
    }

    @Test func aControlTheCameraLacksIsDimmed() async throws {
        let rig = try await rig()
        var noFocus = Self.ranges
        noFocus.hasFocus = false
        await rig.fake.setRanges(noFocus)
        await rig.model.refreshReadouts(from: rig.fake)
        #expect(rig.model.readout(for: .focus).isDimmed)
        #expect(!rig.model.readout(for: .focus).isAvailable)
        for control in ManualControl.allCases where control != .focus {
            #expect(!rig.model.readout(for: control).isDimmed, "\(control)")
        }
    }

    @Test func evIsDimmedWhileExposureIsManual() async throws {
        let rig = try await rig()
        #expect(!rig.model.readout(for: .bias).isDimmed)
        rig.model.setControl(.iso, step: 6)
        await rig.model.manualApplyTask?.value
        let state = rig.model.readout(for: .bias)
        #expect(state.isDimmed)
        #expect(!state.isAvailable)
        #expect(!rig.model.readout(for: .iso).isDimmed)
    }

    // MARK: The Simulator

    @Test func theSimulatorReseedsItsRangesAndReadoutsWhenItsConfigurationChanges() throws {
        let model = try simulator(["app", "-mode", "photo"])
        model.toggleControl(.shutter)
        model.setControl(.shutter, step: 10)
        let photoLongest = try #require(model.scale(for: .shutter)).values.last
        #expect(photoLongest == 1)
        model.mode = .video
        expectAutomaticAndClosedWithoutSession(model)
        let video = SimulatedCamera.ranges(mode: .video, frameRate: model.record.frameRate)
        #expect(model.manualRanges == video)
        #expect(model.shownReadouts == SimulatedCamera.readouts(mode: .video, frameRate: model.record.frameRate))
        #expect(try #require(model.scale(for: .shutter)).values.last != 1)
        model.toggleControl(.iso)
        model.setControl(.iso, step: 3)
        model.record = Self.otherRecord
        expectAutomaticAndClosedWithoutSession(model)
        #expect(model.manualRanges == SimulatedCamera.ranges(mode: .video, frameRate: model.record.frameRate))
        #expect(model.shownReadouts == SimulatedCamera.readouts(mode: .video, frameRate: model.record.frameRate))
        #expect(model.readout(for: .iso).isAvailable)
    }

    func expectAutomaticAndClosedWithoutSession(_ model: CameraModel, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(model.manual == .automatic, sourceLocation: sourceLocation)
        #expect(model.openControl == nil, sourceLocation: sourceLocation)
    }

    // MARK: Exposure bias and the Camera Control

    func liveBias(_ bias: Float) -> LiveReadouts {
        var readouts = Self.live
        readouts.exposureBias = bias
        return readouts
    }

    @Test func evFollowsTheCameraControlWhenItMovesTheBias() async throws {
        let rig = try await rig()
        rig.model.toggleControl(.bias)
        let scale = try #require(rig.model.scale(for: .bias))
        rig.model.setControl(.bias, step: scale.step(nearest: 1))
        rig.model.setControl(.focus, step: 30)
        await rig.model.manualApplyTask?.value
        let appliedBias = try #require(rig.model.manual.bias)
        // The camera shows the bias the app set: the app's value stays, within the device's float noise.
        await rig.fake.setReadouts(liveBias(appliedBias + 0.001))
        await rig.model.refreshReadouts(from: rig.fake)
        #expect(rig.model.manual.bias == appliedBias)
        // The Camera Control moves it.
        await rig.fake.setReadouts(liveBias(-0.7))
        await rig.model.refreshReadouts(from: rig.fake)
        #expect(rig.model.manual.bias == nil)
        #expect(rig.model.appliedManual.bias == nil)
        #expect(rig.model.readout(for: .bias).text == ManualControl.bias.text(-0.7))
        #expect(rig.model.manual.focus != nil)
        rig.model.apply(.interrupted(.cameraInUse))
        rig.model.apply(.interruptionEnded)
        await rig.model.manualApplyTask?.value
        let last = try #require(await rig.fake.manualApplies.last)
        #expect(last.reapplyingAll)
        #expect(last.settings.bias == nil)
        #expect(last.settings.focus == rig.model.manual.focus)
    }

    @Test func evKeepsTheAppsValueWhileItsOwnApplyIsInFlight() async throws {
        let rig = try await rig()
        let scale = try #require(rig.model.scale(for: .bias))
        rig.model.setControl(.bias, step: scale.step(nearest: 1))
        await rig.model.manualApplyTask?.value
        let first = try #require(rig.model.manual.bias)
        await rig.fake.setReadouts(liveBias(first))
        await rig.fake.holdManual()
        rig.model.setControl(.bias, step: scale.step(nearest: -1))
        #expect(await until { await rig.fake.manualApplies.count == 2 })
        let second = try #require(rig.model.manual.bias)
        #expect(second != first)
        // The poll sees the old bias while the new one is on its way.
        await rig.model.refreshReadouts(from: rig.fake)
        #expect(rig.model.manual.bias == second)
        #expect(rig.model.appliedManual.bias == first)
        await rig.fake.resumeManual()
        await rig.model.manualApplyTask?.value
        #expect(rig.model.manual.bias == second)
    }
}
