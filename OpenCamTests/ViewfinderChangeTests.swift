import Foundation
import Testing
@testable import OpenCam

/// The flag the viewfinder's blur follows: up at the press of a change that pauses the picture, down a settle time after the
/// last queued change has finished, by success or failure.
@MainActor @Suite struct ViewfinderChangeTests {
    func deviceModel(_ fake: FakeSessionConfigurator, mode: CaptureMode = .video) throws -> CameraModel {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.mode = mode
        model.phase = .ready
        model.viewfinderSettle = .milliseconds(20)
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return model
    }

    func configuration(of model: CameraModel) throws -> SessionConfiguration {
        try #require(model.sessionConfiguration)
    }

    @Test func aModeChangeBlursAtOnceAndClearsAfterTheConfigure() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        await fake.holdConfigures()
        model.mode = .photo
        #expect(model.isViewfinderChanging)
        #expect(await fake.applied.isEmpty)
        await fake.resumeConfigures()
        await model.waitForQueuedConfigures()
        #expect(await fake.applied.count == 1)
        #expect(await eventually { !model.isViewfinderChanging })
    }

    @Test func twoQuickChangesClearOnce() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        await fake.holdConfigures()
        model.mode = .photo
        // The first configure is waiting; the lens changes to another camera behind it.
        try await Task.sleep(for: .milliseconds(50))
        model.selectLens("ultraWide")
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.isViewfinderChanging)
        await fake.resumeConfigures()
        await model.waitForQueuedConfigures()
        // The first configure was already running, so both ran; only the last one lowers the flag, once it has settled.
        #expect(await fake.applied.map(\.lens.id).last == "ultraWide")
        #expect(await eventually { !model.isViewfinderChanging })
    }

    @Test func aFailedConfigureClears() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: ["ultraWide"])
        let model = try deviceModel(fake)
        let lensID = model.lensID, mode = model.mode
        model.selectLens("ultraWide")
        #expect(model.isViewfinderChanging)
        await model.waitForQueuedConfigures()
        #expect(await eventually { !model.isViewfinderChanging })
        #expect(model.lensID == lensID); #expect(model.mode == mode)
    }

    @Test func aRecorderSwitchPausesThePicture() async throws {
        let model = try deviceModel(FakeSessionConfigurator(failingLensIDs: []))
        let system = try configuration(of: model)
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .hlg)
        var writer = try configuration(of: model)
        writer.recorder = .writer
        #expect(system.recorder == .system)
        #expect(ViewfinderChange.pausesPicture(from: system, to: writer))
        #expect(ViewfinderChange.pausesPicture(from: writer, to: system))
    }

    @Test func aZoomOnlyChangeDoesNotBlur() async throws {
        let model = try deviceModel(FakeSessionConfigurator(failingLensIDs: []))
        let base = try configuration(of: model)
        let wide = try #require(model.capabilities.lenses.first { $0.id == "wide" })
        let zoomed = try #require(model.capabilities.lenses.first { $0.id == "wide@2" })
        let other = try #require(model.capabilities.lenses.first { $0.id == "ultraWide" })
        #expect(wide.deviceUniqueID == zoomed.deviceUniqueID); #expect(wide.deviceUniqueID != other.deviceUniqueID)

        var onWide = base; onWide.lens = wide
        var onZoomed = base; onZoomed.lens = zoomed
        var onOther = base; onOther.lens = other
        #expect(!ViewfinderChange.pausesPicture(from: onWide, to: onZoomed))
        #expect(ViewfinderChange.pausesPicture(from: onWide, to: onOther))
        var otherMode = onWide; otherMode.mode = onWide.mode == .video ? .photo : .video
        #expect(ViewfinderChange.pausesPicture(from: onWide, to: otherMode))
        var otherVideo = onWide; otherVideo.video = nil
        #expect(onWide.video != nil); #expect(ViewfinderChange.pausesPicture(from: onWide, to: otherVideo))
        var otherPhoto = onWide; otherPhoto.photo = nil
        #expect(onWide.photo != nil); #expect(ViewfinderChange.pausesPicture(from: onWide, to: otherPhoto))
        var otherSound = onWide; otherSound.includesAudio.toggle()
        #expect(ViewfinderChange.pausesPicture(from: onWide, to: otherSound))
        var otherFrames = onWide; otherFrames.needsFrames.toggle()
        #expect(ViewfinderChange.pausesPicture(from: onWide, to: otherFrames))
        #expect(!ViewfinderChange.pausesPicture(from: nil, to: onWide))
    }

    @Test func aRefusedChangeDoesNotBlur() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        model.isRecording = true
        model.selectLens("ultraWide")
        #expect(!model.isViewfinderChanging)
        model.isRecording = false

        let held = try deviceModel(FakeSessionConfigurator(failingLensIDs: []))
        held.openLibrary()
        await held.libraryHandoff?.value
        #expect(held.isHeldForLibrary)
        held.selectLens("ultraWide")
        #expect(!held.isViewfinderChanging)
    }
}
