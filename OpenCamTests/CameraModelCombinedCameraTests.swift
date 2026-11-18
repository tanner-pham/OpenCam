import Foundation
import Testing
@testable import OpenCam

/// What the model asks the session for when the device has a combined back camera, and how it learns of that camera at launch.
@MainActor @Suite struct CameraModelCombinedCameraTests {
    static let combined = CombinedCamera(
        deviceUniqueID: "fixture-dual", baseZoomByDeviceID: ["fixture-ultraWide": 1, "fixture-wide": 2],
        formats: [3840, 1920].flatMap { width in
            [CombinedFormat(width: width, height: width * 9 / 16, colourSpaces: [0, 1, 2], frameRateRanges: [1...60], maxZoomFactor: 100)]
        })

    struct Rig {
        let model: CameraModel
        let fake: FakeSessionConfigurator
        let defaults: UserDefaults
    }

    private func rig(combined: CombinedCamera? = combined, mode: CaptureMode = .video) throws -> Rig {
        let defaults = try Fixture.freshDefaults()
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: defaults,
                                captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.viewfinderSettle = .milliseconds(20)
        model.combinedCamera = combined
        model.mode = mode
        model.phase = .ready
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return Rig(model: model, fake: fake, defaults: defaults)
    }

    private func model(combined: CombinedCamera? = combined, mode: CaptureMode = .video) throws -> CameraModel {
        try rig(combined: combined, mode: mode).model
    }

    /// A model on the combined camera at `wide` (zoom 2) with the fake's manual ranges read.
    private func readyRig() async throws -> Rig {
        let rig = try rig()
        rig.model.selectLens("wide")
        await rig.model.waitForQueuedConfigures()
        await rig.model.refreshReadouts(from: rig.fake)
        return rig
    }

    private func eventuallyAsync(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    /// The first manual shutter, waited out: the move to the lens's own camera and the values sent to it.
    private func setShutterByHand(_ rig: Rig) async {
        rig.model.setControl(.shutter, step: 3)
        await rig.model.waitForQueuedConfigures()
        let fake = rig.fake
        let reapplied = await eventuallyAsync { await fake.manualApplies.last?.reapplyingAll == true }
        #expect(reapplied)
    }

    @Test func videoOnABackLensNamesTheCombinedCamera() throws {
        let model = try model()
        model.selectLens("wide")
        #expect(model.sessionConfiguration?.combined == CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 2))
        model.selectLens("ultraWide")
        #expect(model.sessionConfiguration?.combined == CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 1))
        model.selectLens("wide@2")
        #expect(model.sessionConfiguration?.combined == CombinedLens(deviceUniqueID: "fixture-dual", zoomFactor: 4))
    }

    @Test func photoModeAndFrontLensesKeepTheirOwnCamera() throws {
        let model = try model(mode: .photo)
        #expect(model.sessionConfiguration?.combined == nil)
        model.mode = .video
        model.selectLens("outer")
        #expect(model.sessionConfiguration?.combined == nil)
    }

    @Test func noCombinedCameraChangesNothing() throws {
        let model = try model(combined: nil)
        model.selectLens("wide")
        #expect(model.sessionConfiguration?.combined == nil)
    }

    @Test func aSourceWithACombinedCameraHandsItToTheModel() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        var fixture = try Fixture.load()
        fixture.osBuild = DeviceIdentity.osBuild(); fixture.modelIdentifier = DeviceIdentity.modelIdentifier()
        try CapabilityCache(directory: directory).save(fixture)
        let lenses = fixture.lenses, combined = Self.combined
        let source = CapabilitySource(cacheDirectory: directory, documentsDirectory: nil, discoverLenses: { lenses },
                                      scan: { _ throws(CameraSessionError) in [] },
                                      combinedCamera: { combined })
        let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
        let model = CameraModel(config: LaunchConfig(), capabilities: empty, isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source)
        model.mode = .video
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        #expect(await model.startCamera(on: fake, savedStart: nil))
        #expect(model.combinedCamera == Self.combined)
        #expect(await fake.applied.first?.combined != nil)
    }

    @Test func aLensTapInsideTheCombinedCameraDoesNotBlur() async throws {
        let rig = try await readyRig()
        let before = await rig.fake.applied.count
        rig.model.selectLens("ultraWide")
        #expect(!rig.model.isViewfinderChanging)
        await rig.model.waitForQueuedConfigures()
        #expect(!rig.model.isViewfinderChanging)
        #expect(await rig.fake.applied.count == before + 1)
        #expect(await rig.fake.applied.last?.combined?.zoomFactor == 1)
        rig.model.selectLens("wide@2")
        #expect(!rig.model.isViewfinderChanging)
        await rig.model.waitForQueuedConfigures()
        #expect(!rig.model.isViewfinderChanging)
        #expect(await rig.fake.applied.last?.combined?.zoomFactor == 4)
    }

    @Test func aLensTapReturnsTheControlsToAutomatic() async throws {
        let rig = try await readyRig()
        rig.model.setControl(.focus, step: 2)
        #expect(rig.model.manual != .automatic)
        rig.model.selectLens("ultraWide")
        await rig.model.waitForQueuedConfigures()
        #expect(rig.model.manual == .automatic)
    }

    @Test func aFrontLensLeavesTheCombinedCameraBehindTheBlur() async throws {
        let rig = try await readyRig()
        rig.model.selectLens("outer")
        #expect(rig.model.isViewfinderChanging)
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.applied.last?.combined == nil)
        _ = await eventually { !rig.model.isViewfinderChanging }
        rig.model.selectLens("wide")
        #expect(rig.model.isViewfinderChanging)
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.applied.last?.combined != nil)
    }

    @Test func theFirstManualShutterMovesToTheLensesOwnCamera() async throws {
        let rig = try await readyRig()
        let lens = rig.model.currentLens
        rig.model.setControl(.shutter, step: 3)
        #expect(rig.model.isViewfinderChanging)
        await rig.model.waitForQueuedConfigures()
        #expect(await eventuallyAsync { await rig.fake.manualApplies.last?.reapplyingAll == true })
        #expect(await rig.fake.applied.last?.lens == lens)
        #expect(await rig.fake.applied.last?.combined == nil)
        #expect(rig.model.manual.exposure != .automatic)
        let last = await rig.fake.manualApplies.last
        #expect(last?.settings.exposure != .automatic)
    }

    @Test func aLensTapAfterAManualExposureReturnsToTheCombinedCamera() async throws {
        let rig = try await readyRig()
        await setShutterByHand(rig)
        let count = await rig.fake.applied.count
        rig.model.selectLens("ultraWide")
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.applied.count == count + 1)
        #expect(await rig.fake.applied.last?.combined?.zoomFactor == 1)
        #expect(rig.model.manual == .automatic)
    }

    @Test func aConfigureRequestWithNothingChangedKeepsTheManualExposure() async throws {
        let rig = try await readyRig()
        await setShutterByHand(rig)
        let count = await rig.fake.applied.count
        #expect(rig.model.enqueueConfigure() == nil)
        #expect(await rig.fake.applied.count == count)
        #expect(rig.model.manual.exposure != .automatic)
    }

    @Test func shutterAndISOWaitWhileRecordingOnTheCombinedCamera() async throws {
        let rig = try await readyRig()
        rig.model.isRecording = true
        let shutter = rig.model.readout(for: .shutter)
        #expect(!shutter.isAvailable)
        #expect(shutter.accessibilityValue == "Not available while recording")
        let applies = await rig.fake.manualApplies.count
        rig.model.setControl(.iso, step: 2)
        #expect(rig.model.manual == .automatic)
        #expect(await rig.fake.manualApplies.count == applies)
        #expect(rig.model.readout(for: .focus).isAvailable)
    }

    @Test func theSavedStartIsTheAutomaticCamera() async throws {
        let rig = try await readyRig()
        await setShutterByHand(rig)
        let working = try #require(rig.model.lastWorking)
        #expect(working.configuration.combined == nil)
        rig.model.saveStart(working)
        let saved = try #require(SavedStart.load(from: rig.defaults))
        #expect(saved.configuration.combined?.zoomFactor == 2)
    }

    @Test func aFailedMoveReturnsExposureToAutomatic() async throws {
        let rig = try await readyRig()
        await rig.fake.setFailingLensIDs(["wide"])
        rig.model.setControl(.shutter, step: 3)
        await rig.model.waitForQueuedConfigures()
        #expect(rig.model.manual.exposure == .automatic)
        #expect(rig.model.requestedConfiguration?.combined != nil)
    }

    @Test func returningExposureToAutomaticDoesNotMoveTheCamera() async throws {
        let rig = try await readyRig()
        await setShutterByHand(rig)
        rig.model.setControl(.focus, step: 2)
        rig.model.setAutomatic(.shutter)
        let count = await rig.fake.applied.count
        #expect(rig.model.enqueueConfigure() == nil)
        #expect(await rig.fake.applied.count == count)
        #expect(rig.model.manual.focus != nil)
        rig.model.selectLens("ultraWide")
        #expect(rig.model.isViewfinderChanging)
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.applied.last?.combined?.zoomFactor == 1)
    }

    @Test func aSecondShutterStepDuringTheMoveChangesNothing() async throws {
        let rig = try await readyRig()
        await rig.fake.holdConfigures()
        rig.model.setControl(.shutter, step: 3)
        let manual = rig.model.manual
        rig.model.setControl(.shutter, step: 5)
        #expect(rig.model.manual == manual)
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
        let fake = rig.fake
        let didApply = await eventuallyAsync {
            guard await fake.manualApplies.last?.reapplyingAll == true else { return false }
            return await fake.appliedManual != nil
        }
        #expect(didApply)
        #expect(await rig.fake.applied.last?.combined == nil)
        #expect(rig.model.manual.exposure != .automatic)
        #expect(rig.model.notice == nil)
    }

    @Test func anOptionTheCombinedCameraFailsUsesTheLensesOwnCameraNextTime() async throws {
        let rig = try await readyRig()
        await rig.fake.setFailsCombined(true)
        let appliedBefore = await rig.fake.applied.count
        rig.model.selectLens("ultraWide")
        await rig.model.waitForQueuedConfigures()
        // The configure failed: nothing was applied and the selection is back on the lens that works.
        #expect(await rig.fake.applied.count == appliedBefore)
        #expect(rig.model.lensID == "wide")
        rig.model.selectLens("ultraWide")
        await rig.model.waitForQueuedConfigures()
        #expect(await rig.fake.applied.last?.lens.id == "ultraWide")
        #expect(await rig.fake.applied.last?.combined == nil)
        #expect(rig.model.lensID == "ultraWide")
    }

    @Test func anOpenShutterSliderClosesWhenARecordingStarts() async throws {
        let rig = try await readyRig()
        rig.model.toggleControl(.shutter)
        #expect(rig.model.openControl == .shutter)
        await (try #require(rig.model.startRecording())).value
        #expect(rig.model.openControl == nil)
    }

    @Test func anOpenFocusSliderStaysOpenWhenARecordingStarts() async throws {
        let rig = try await readyRig()
        rig.model.toggleControl(.focus)
        #expect(rig.model.openControl == .focus)
        await (try #require(rig.model.startRecording())).value
        #expect(rig.model.openControl == .focus)
    }
}
