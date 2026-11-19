import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

/// Pinch to zoom, through the model and a fake session.
@MainActor @Suite struct CameraModelZoomTests {
    struct Rig {
        let model: CameraModel
        let fake: FakeSessionConfigurator
    }

    /// Photo mode starts on a HEIF selection, so a pinch is allowed (Bayer RAW needs a zoom of exactly 1).
    func rig(mode: CaptureMode = .video, combined: CombinedCamera? = nil) async throws -> Rig {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let source = CapabilitySource(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                                      documentsDirectory: nil, discoverLenses: { [] }, scan: { _ in [] })
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source, captureStore: try CaptureStore(directory: TestFiles.directory()), isLibraryAvailable: true)
        model.combinedCamera = combined
        model.mode = mode
        if let heif = model.photoResolver.select(.format, chipID: PhotoFormat.heif.rawValue, in: model.photo) { model.photo = heif }
        model.phase = .ready
        model.viewfinderSettle = .milliseconds(20)
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return Rig(model: model, fake: fake)
    }

    func until(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    /// The fixture's own 1x lens of that kind.
    func lens(_ rig: Rig, _ kind: LensKind) -> String {
        rig.model.capabilities.lenses.first { $0.kind == kind && $0.zoomFactor == 1 }?.id ?? ""
    }

    /// Waits for the configure and for the picture to settle, which a mode, lens or format change pauses.
    func settle(_ rig: Rig) async {
        await rig.model.waitForQueuedConfigures()
        _ = await eventually { rig.model.canAim }
    }

    /// Pinches to `factor` from no pinch and waits until the session has heard it.
    func pinch(_ rig: Rig, to factor: Double) async {
        rig.model.setPinch(magnification: factor, from: 1)
        _ = await eventually { rig.model.zoomApplies.isIdle }
    }

    @Test func aPinchSendsTheFactorWithoutConfiguring() async throws {
        let rig = try await rig()
        let manual = rig.model.manual
        rig.model.setPinch(magnification: 1.6, from: 1)
        #expect(await eventually { rig.model.zoomApplies.isIdle })
        #expect(await rig.fake.zoomRequests == [1.6])
        #expect(await rig.fake.calls == ["zoom"])
        #expect(rig.model.manual == manual)
        #expect(!rig.model.isViewfinderChanging)
        #expect(rig.model.pinch == 1.6)
    }

    @Test func aBurstSendsOnlyTheLatest() async throws {
        let rig = try await rig()
        await rig.fake.holdZoom()
        rig.model.setPinch(magnification: 1.2, from: 1)
        #expect(await until { await rig.fake.zoomRequests.count == 1 })
        rig.model.setPinch(magnification: 1.4, from: 1)
        rig.model.setPinch(magnification: 1.8, from: 1)
        await rig.fake.resumeZoom()
        #expect(await eventually { rig.model.zoomApplies.isIdle })
        #expect(await rig.fake.zoomRequests == [1.2, 1.8])
        #expect(rig.model.pinch == 1.8)
    }

    @Test func aLensTapResetsThePinchToOne() async throws {
        let rig = try await rig()
        await pinch(rig, to: 1.6)
        #expect(rig.model.lensID != lens(rig, .ultraWide))
        rig.model.selectLens(lens(rig, .ultraWide))
        await settle(rig)
        #expect(rig.model.lensID == lens(rig, .ultraWide))
        #expect(rig.model.pinch == 1)
        #expect(await rig.fake.pinch == 1)
        #expect(rig.model.zoomLabel == nil)
    }

    @Test func aModeSwitchAndAFormatChangeResetIt() async throws {
        let rig = try await rig()
        await pinch(rig, to: 1.6)
        rig.model.toggleMode()
        await settle(rig)
        #expect(rig.model.pinch == 1)
        #expect(await rig.fake.pinch == 1)
        // Photo mode is on HEIF here; the format row moving to RAW + HEIF is a format change.
        await pinch(rig, to: 2)
        #expect(rig.model.pinch == 2)
        let other = try #require(rig.model.photoResolver.select(.format, chipID: PhotoFormat.rawPlusHEIF.rawValue, in: rig.model.photo))
        rig.model.photo = other
        await settle(rig)
        #expect(rig.model.pinch == 1)
        #expect(await rig.fake.pinch == 1)
    }

    @Test func aLookChangeKeepsIt() async throws {
        let rig = try await rig()
        // The fake keeps the last configuration it was given, which the rule compares with.
        rig.model.selectLens(lens(rig, .ultraWide))
        await settle(rig)
        rig.model.looks = [Look(id: UUID(), name: "Warm", adjustments: Adjustments().setting(.temperature, to: 20), createdAt: .now)]
        await pinch(rig, to: 1.6)
        let configures = await rig.fake.applied.count
        rig.model.selectLook(rig.model.looks[0].id)
        await settle(rig)
        #expect(await rig.fake.applied.count == configures + 1)
        #expect(await rig.fake.applied.last?.needsFrames == true)
        #expect(rig.model.pinch == 1.6)
        #expect(await rig.fake.pinch == 1.6)
    }

    @Test func aPinchWorksWhileRecording() async throws {
        let rig = try await rig()
        rig.model.isRecording = true
        rig.model.setPinch(magnification: 1.6, from: 1)
        #expect(await eventually { rig.model.zoomApplies.isIdle })
        #expect(await rig.fake.zoomRequests == [1.6])
        #expect(rig.model.pinch == 1.6)
    }

    @Test func theSessionsLimitIsAdopted() async throws {
        let rig = try await rig()
        await rig.fake.setZoomLimit(5)
        rig.model.setPinch(magnification: 8, from: 1)
        #expect(await eventually { rig.model.zoomApplies.isIdle })
        #expect(await eventually { rig.model.pinch == 5 })
        #expect(rig.model.zoomLabel == "5x")
    }

    @Test func theStripLabelFollowsThePinch() async throws {
        let rig = try await rig()
        rig.model.selectLens(lens(rig, .wide))
        await settle(rig)
        #expect(rig.model.zoomLabel == nil)
        await pinch(rig, to: 1.6)
        #expect(rig.model.zoomLabel == "1.6x")
    }

    @Test func noPinchWithoutACamera() async throws {
        let rig = try await rig()
        rig.model.phase = .failed("The camera could not start.")
        rig.model.setPinch(magnification: 2, from: 1)
        #expect(rig.model.pinch == 1)
        #expect(rig.model.zoomLabel == nil)
        #expect(rig.model.zoomApplies.isIdle)
        #expect(await rig.fake.zoomRequests.isEmpty)
    }

    @Test func aPinchDoesNothingWhileThePhotoFormatIsRAW() async throws {
        let rig = try await rig(mode: .photo)
        #expect(rig.model.canPinch)
        let raw = try #require(rig.model.photoResolver.select(.format, chipID: PhotoFormat.rawPlusHEIF.rawValue, in: rig.model.photo))
        rig.model.photo = raw
        await settle(rig)
        #expect(!rig.model.canPinch)
        rig.model.setPinch(magnification: 2, from: 1)
        #expect(rig.model.pinch == 1)
        #expect(rig.model.zoomLabel == nil)
        #expect(await rig.fake.zoomRequests.isEmpty)
        // Video has no such limit, whatever the photo format is.
        rig.model.toggleMode()
        await settle(rig)
        #expect(rig.model.canPinch)
    }

    static let combined = CombinedCamera(
        deviceUniqueID: "fixture-dual", baseZoomByDeviceID: ["fixture-ultraWide": 1, "fixture-wide": 2],
        formats: [3840, 1920].map { width in
            CombinedFormat(width: width, height: width * 9 / 16, colourSpaces: [0, 1, 2], frameRateRanges: [1...60], maxZoomFactor: 100)
        })

    @Test func aLensThereAndBackWhileAConfigureRunsLeavesBothAtOne() async throws {
        let rig = try await rig()
        let ultra = lens(rig, .ultraWide), wide = lens(rig, .wide)
        rig.model.selectLens(ultra)
        await settle(rig)
        rig.model.looks = [Look(id: UUID(), name: "Warm", adjustments: Adjustments().setting(.temperature, to: 20), createdAt: .now)]
        await pinch(rig, to: 3)
        #expect(await rig.fake.pinch == 3)
        // A look configure holds the chain; the lens change and the change back queue behind it, so the middle one is skipped and
        // the session sees the same lens in the two configures it is given, which keeps its pinch.
        await rig.fake.holdConfigures()
        rig.model.selectLook(rig.model.looks[0].id)
        rig.model.selectLens(wide)
        rig.model.selectLens(ultra)
        #expect(rig.model.pinch == 1)
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
        #expect(await eventually { rig.model.zoomApplies.isIdle })
        #expect(rig.model.pinch == 1)
        #expect(await rig.fake.pinch == 1)
    }

    @Test func aPinchRightAfterALensTapIsAppliedAfterItsConfigure() async throws {
        let rig = try await rig(combined: Self.combined)
        rig.model.selectLens(lens(rig, .ultraWide))
        await settle(rig)
        await rig.fake.holdConfigures()
        rig.model.selectLens(lens(rig, .wide))
        // A lens change inside the combined camera does not pause the picture, so a pinch may start at once.
        #expect(rig.model.canPinch)
        rig.model.setPinch(magnification: 1.5, from: 1)
        try await Task.sleep(for: .milliseconds(80))
        #expect(await rig.fake.zoomRequests.isEmpty)
        await rig.fake.resumeConfigures()
        await rig.model.waitForQueuedConfigures()
        #expect(await eventually { rig.model.zoomApplies.isIdle })
        #expect(await rig.fake.zoomRequests == [1.5])
        let calls = await rig.fake.calls
        #expect(try #require(calls.lastIndex(of: "zoom")) > (try #require(calls.lastIndex(of: "configure"))))
        #expect(rig.model.pinch == 1.5)
        #expect(await rig.fake.pinch == 1.5)
    }

    @Test func theLibraryAndBackKeepsThePinch() async throws {
        let rig = try await rig()
        rig.model.selectLens(lens(rig, .ultraWide))
        await settle(rig)
        await pinch(rig, to: 1.6)
        #expect(rig.model.zoomLabel == "0.8x")
        rig.model.openLibrary()
        await rig.model.libraryHandoff?.value
        #expect(await rig.fake.releaseCount == 1)
        rig.model.isLibraryPresented = false
        await rig.model.closeLibrary()
        #expect(await rig.fake.isRunning)
        #expect(rig.model.pinch == 1.6)
        #expect(rig.model.zoomLabel == "0.8x")
        #expect(await rig.fake.pinch == 1.6)
    }

    @Test func pastTheLimitTheLabelDoesNotMove() async throws {
        let rig = try await rig()
        rig.model.selectLens(lens(rig, .wide))
        await settle(rig)
        await rig.fake.setZoomLimit(5)
        await pinch(rig, to: 8)
        #expect(rig.model.pinch == 5)
        // The fingers keep spreading: the label stays at the limit from the first change on.
        rig.model.setPinch(magnification: 9, from: 1)
        #expect(rig.model.pinch == 5)
        #expect(rig.model.zoomLabel == "5x")
        rig.model.setPinch(magnification: 3, from: 1)
        #expect(rig.model.pinch == 3)
        // A lens change forgets the limit.
        rig.model.selectLens(lens(rig, .ultraWide))
        await settle(rig)
        await rig.fake.setZoomLimit(10)
        rig.model.setPinch(magnification: 8, from: 1)
        #expect(rig.model.pinch == 8)
    }
}
