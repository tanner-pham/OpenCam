import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct CameraModelEventTests {
    @Test func pressureIsKeptApartFromTheNotice() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        model.apply(.interrupted(.cameraInUse))
        model.apply(.pressure(.serious, isThermal: true))
        #expect(model.notice == "Camera paused. Another app is using it.")
        #expect(model.pressureLevel == .serious); #expect(model.isThermalPressure)
        model.apply(.interruptionEnded); #expect(model.notice == nil); #expect(model.pressureLevel == .serious)
    }

    @Test func runtimeErrorThatRecoversEndsReady() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        model.apply(.interrupted(.other))
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11819}"))
        #expect(model.phase == .failed("The camera stopped."))
        model.apply(.restarted)
        #expect(model.phase == .ready); #expect(model.notice == nil)
    }

    @Test func theCameraIsUsableForASweepOnlyWhenReadyAndNotInterrupted() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        #expect(!model.isCameraUsable)
        model.phase = .ready; #expect(model.isCameraUsable)
        model.apply(.interrupted(.cameraInUse)); #expect(!model.isCameraUsable)
        model.apply(.interruptionEnded); #expect(model.isCameraUsable)
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11800}")); #expect(!model.isCameraUsable)
    }

    @Test func interruptionIsStateThatEndsOrRestarts() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        model.phase = .ready
        model.apply(.interrupted(.background))
        #expect(model.isInterrupted); #expect(!model.isCameraUsable); #expect(model.notice == nil)
        model.apply(.interruptionEnded)
        #expect(!model.isInterrupted); #expect(model.isCameraUsable)
        model.apply(.interrupted(.cameraInUse))
        #expect(model.isInterrupted)
        model.apply(.restarted)
        #expect(!model.isInterrupted); #expect(model.isCameraUsable)
    }

    func attachedModel(failing: Bool = false) throws -> (CameraModel, FakeSessionConfigurator) {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.phase = .ready
        let fake = FakeSessionConfigurator(failingLensIDs: failing ? [model.lensID] : [])
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return (model, fake)
    }

    /// A restart while the Library is open and the camera already released keeps it released, with no second release.
    @Test func aRestartUnderTheLibraryAfterTheReleaseStaysReleased() async throws {
        let (model, fake) = try attachedModel()
        model.openLibrary()
        await model.libraryHandoff?.value
        model.apply(.restarted)
        #expect(model.phase == .released)
        await model.libraryHandoff?.value
        #expect(await fake.releaseCount == 1); #expect(await !fake.holdsCamera)
    }

    /// The Library opened while the camera had failed, so nothing was released; the session coming back under the cover lets
    /// the camera go.
    @Test func aRestartUnderALibraryOpenedWhileFailedReleasesTheCamera() async throws {
        let (model, fake) = try attachedModel()
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11819}"))
        model.openLibrary()
        #expect(model.libraryHandoff == nil)
        model.apply(.restarted)
        #expect(model.phase == .released)
        await model.libraryHandoff?.value
        #expect(await fake.calls == ["release"]); #expect(await !fake.holdsCamera)
    }

    /// After a failed return the session holds no camera; a restart with the Library closed does not claim it is ready, and
    /// the next close of the Library still retries.
    @Test func aRestartAfterAFailedReturnDoesNotClaimReady() async throws {
        let (model, fake) = try attachedModel(failing: true)
        model.openLibrary()
        await model.libraryHandoff?.value
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(model.phase == .failed("The camera could not start."))
        model.apply(.restarted)
        #expect(model.phase == .failed("The camera could not start."))
        await fake.setFailingLensIDs([])
        model.openLibrary()
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(model.phase == .ready); #expect(await fake.calls == ["release", "configure", "start"])
    }

    /// With no Library involved a restart ends ready, as before.
    @Test func anOrdinaryRestartEndsReady() async throws {
        let (model, fake) = try attachedModel()
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11819}"))
        model.apply(.restarted)
        #expect(model.phase == .ready); #expect(model.libraryHandoff == nil); #expect(await fake.calls.isEmpty)
    }

    @Test func runtimeErrorThatDoesNotRecoverStaysFailed() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11800}"))
        model.apply(.pressure(.fair, isThermal: false))
        #expect(model.phase == .failed("The camera stopped."))
    }

    @Test func unavailableMicrophoneReadsAsDeniedAndKeepsVideo() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        #expect(model.access.recordsSound)
        model.apply(.microphoneUnavailable("[CameraSession:configure] Cannot add input — {lens: microphone}"))
        #expect(model.access == CaptureAccess(camera: .authorized, microphone: .denied)); #expect(!model.access.recordsSound)
        #expect(model.access.canUseCamera); #expect(model.phase == .simulator); #expect(model.notice == nil)
    }
}
