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
