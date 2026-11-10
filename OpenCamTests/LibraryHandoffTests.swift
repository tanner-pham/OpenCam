import Foundation
import Testing
@testable import OpenCam

/// The camera lets go of its sensor while the Library covers it and takes it back when the Library closes.
@MainActor @Suite struct LibraryHandoffTests {
    func readyModel(failing: Bool = false, isLibraryAvailable: Bool = true) throws -> (CameraModel, FakeSessionConfigurator) {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()), isLibraryAvailable: isLibraryAvailable)
        model.phase = .ready
        let fake = FakeSessionConfigurator(failingLensIDs: failing ? [model.lensID] : [])
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return (model, fake)
    }

    @Test func openReleasesOnceAndCloseReappliesAndStartsOnce() async throws {
        let (model, fake) = try readyModel()
        let selection = try #require(model.sessionConfiguration)
        model.openLibrary()
        #expect(model.isLibraryPresented); #expect(model.phase == .released)
        #expect(model.shownReadouts == LiveReadouts()); #expect(model.shownMeterLevels == [0, 0]); #expect(model.summaryParts == ["--"])
        await model.libraryHandoff?.value
        #expect(await fake.calls == ["release"]); #expect(await !fake.holdsCamera); #expect(await !fake.isRunning)

        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(await fake.calls == ["release", "configure", "start"]); #expect(await fake.applied.last == selection)
        #expect(await fake.isRunning); #expect(model.phase == .ready)
    }

    @Test func aSecondOpenBeforeTheCloseHasFinishedCannotReleaseTwice() async throws {
        let (model, fake) = try readyModel()
        model.openLibrary()
        model.openLibrary()
        model.isLibraryPresented = false
        let closing = Task { await model.closeLibrary() }
        model.openLibrary()
        await closing.value
        await model.libraryHandoff?.value
        #expect(await fake.releaseCount == 1); #expect(await fake.calls == ["release"]); #expect(model.phase == .released)

        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(await fake.calls == ["release", "configure", "start"]); #expect(model.phase == .ready)
    }

    @Test func aFailureOnReturnEndsInFailed() async throws {
        let (model, fake) = try readyModel(failing: true)
        model.openLibrary()
        await model.libraryHandoff?.value
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(model.phase == .failed("The camera could not start.")); #expect(await !fake.isRunning)
        #expect(await fake.calls == ["release"])
    }

    /// Closed before the release ran: the session never let go, so nothing is released or configured and the camera is back.
    @Test func aCloseBeforeTheReleaseRanLeavesTheSessionAlone() async throws {
        let (model, fake) = try readyModel()
        model.openLibrary()
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(await fake.calls.isEmpty); #expect(await fake.isRunning); #expect(model.phase == .ready)
    }

    @Test func closeRefreshesTheLastCapture() async throws {
        let dir = try TestFiles.directory()
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: dir))
        model.openLibrary(); #expect(model.phase == .simulator)
        try Data("x".utf8).write(to: dir.appending(path: "OC_0004.JPG"))
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(model.lastCapture.map(CaptureStore.clipKey(for:)) == "OC_0004.JPG")
    }

    /// Opened before the camera was ready (the permission prompt, a `-screen library` launch): when `start` reaches ready it
    /// lets the camera go at once, and the close brings it back.
    @Test func aCameraThatBecomesReadyUnderTheLibraryIsReleased() async throws {
        let (model, fake) = try readyModel()
        model.phase = .scanning
        model.openLibrary()
        #expect(model.isLibraryPresented); #expect(model.phase == .scanning); #expect(model.libraryHandoff == nil)
        // What `start` does once its session runs.
        model.phase = .ready
        model.releaseIfLibraryOpen()
        #expect(model.phase == .released)
        await model.libraryHandoff?.value
        #expect(await fake.calls == ["release"]); #expect(await !fake.isRunning)
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(await fake.calls == ["release", "configure", "start"]); #expect(model.phase == .ready)
    }

    /// Without a Library the helper changes nothing.
    @Test func aCameraThatBecomesReadyWithoutTheLibraryStaysReady() async throws {
        let (model, fake) = try readyModel()
        model.releaseIfLibraryOpen()
        #expect(model.phase == .ready); #expect(model.libraryHandoff == nil); #expect(await fake.calls.isEmpty)
    }

    /// Whatever the phase says, a press or a Camera Control click under the Library never captures.
    @Test func nothingIsCapturedWhileTheLibraryIsOpen() async throws {
        let (model, fake) = try readyModel()
        #expect(model.mode == .video); #expect(model.canCapture)
        model.isLibraryPresented = true
        model.phase = .ready
        #expect(!model.canCapture)
        model.capturePressed()
        model.handleCaptureEvent(phase: .ended)
        #expect(!model.isRecording); #expect(await fake.recordingURLs.isEmpty)
        model.mode = .photo
        #expect(!model.canCapture)
        model.isLibraryPresented = false
        #expect(model.canCapture)
    }

    /// A restart reported after the Library opened but before the release finished keeps the camera released.
    @Test func aRestartBeforeTheReleaseFinishesStaysReleased() async throws {
        let (model, fake) = try readyModel()
        model.openLibrary()
        #expect(!model.isCameraReleasedForLibrary)
        model.apply(.restarted)
        #expect(model.phase == .released)
        await model.libraryHandoff?.value
        #expect(model.phase == .released); #expect(await fake.calls == ["release"])
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(model.phase == .ready)
    }

    @Test func aLibraryThatCouldNotBeBuiltSaysSoOnTheCamera() throws {
        let (model, _) = try readyModel(isLibraryAvailable: false)
        #expect(model.canOpenLibrary)
        model.openLibrary()
        #expect(!model.isLibraryPresented); #expect(model.notice == "The library could not be opened."); #expect(model.phase == .ready)
    }
}
