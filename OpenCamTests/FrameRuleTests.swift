import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct FrameRuleTests {
    let uhd = Resolution.named(width: 3840, height: 2160)

    func make() throws -> (CameraModel, Look) {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(), lookStore: looks)
        model.phase = .ready
        return (model, look)
    }

    @Test func noLookMeansTodaysConfiguration() async throws {   // Review Focus 3
        let (model, look) = try make()
        let lens = try #require(model.currentLens)
        let today = SessionConfiguration.make(lens: lens, mode: model.mode, video: model.currentVideoOption, photo: model.currentPhotoOption, access: model.access)
        #expect(model.sessionConfiguration == today); #expect(today.needsFrames == false)
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        model.attachSession(fake, configuredWith: today, selection: model.currentSelection)
        model.selectLook(look.id); try await model.applySelection()
        model.selectLook(nil); try await model.applySelection()
        #expect(await fake.applied.map(\.needsFrames) == [true, false])
        #expect(await fake.applied.last == today)
    }

    @Test func lensModeAndFormatChangesKeepTheViewfinderConsistent() throws {   // Review Focus 5
        let (model, look) = try make()
        model.mode = .video
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .rec709)
        model.selectLook(look.id)
        model.selectLens("ultraWide")
        #expect(model.cameraLook?.id == look.id); #expect(model.viewfinderLook?.id == look.id); #expect(model.sessionConfiguration?.needsFrames == true)
        model.mode = .photo
        #expect(model.viewfinderLook?.id == look.id); #expect(model.sessionConfiguration?.needsFrames == true)

        model.apply(.framesUnavailable)
        #expect(model.cameraLook?.id == look.id); #expect(model.viewfinderLook == nil); #expect(model.sessionConfiguration?.needsFrames == false)
        #expect(model.notice == "The look cannot be shown in the viewfinder with this format."); #expect(model.summaryLookName == "Warm fade")
        model.mode = .video
        #expect(model.notice == nil); #expect(model.sessionConfiguration?.needsFrames == true)   // a new format tries again
        model.framesUnavailable()
        #expect(model.summaryLookName == nil)                                                    // video: the look applies nowhere
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .appleLog)
        #expect(model.cameraLook == nil); #expect(model.notice == "Look turned off. Looks need Rec. 709 or P3.")
        #expect(model.sessionConfiguration?.needsFrames == false)
    }

    /// A look deleted in the Library while the camera is released changes the configuration, but nothing is configured on
    /// the released session: the close applies the new configuration once, then starts.
    @Test func aLookDeletedUnderTheLibraryIsConfiguredOnceOnReturn() async throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()), lookStore: looks)
        model.phase = .ready
        model.selectLook(look.id)
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        #expect(model.sessionConfiguration?.needsFrames == true)

        model.openLibrary()
        await model.libraryHandoff?.value
        try looks.delete(look.id)
        // What the Library's look edits lead to while it is open.
        model.reloadLooks()
        #expect(model.cameraLook == nil)
        await model.waitForQueuedConfigures()
        #expect(await fake.calls == ["release"])

        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(await fake.calls == ["release", "configure", "start"])
        #expect(await fake.applied.last?.needsFrames == false); #expect(model.phase == .ready)
    }
}
