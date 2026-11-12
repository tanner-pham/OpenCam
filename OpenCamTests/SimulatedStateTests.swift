import Testing
@testable import OpenCam

@MainActor
@Suite struct SimulatedStateTests {
    func simulator(_ state: String, mode: String = "video") throws -> CameraModel {
        CameraModel(config: .parse(["app", "-mode", mode, "-state", state]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
    }

    @Test func parsesTheNewStates() {
        #expect(LaunchConfig.parse(["app", "-state", "cameraStopped"]).simulatedState == .cameraStopped)
        #expect(LaunchConfig.parse(["app", "-state", "cameraRestricted"]).simulatedState == .cameraRestricted)
        #expect(LaunchConfig.parse(["app", "-state", "sweepWarning"]).simulatedState == .sweepWarning)
    }

    @Test func cameraStoppedIsTheStateAfterAnUnrecoveredRuntimeError() throws {
        let model = try simulator("cameraStopped")
        #expect(model.phase == .failed(CameraModel.cameraStopped)); #expect(model.isCameraStopped)
        #expect(!model.hasCamera); #expect(model.canOpenRecordSettings)
    }

    @Test func tryAgainInTheSimulatedStoppedCameraLeavesItStopped() async throws {
        let model = try simulator("cameraStopped")
        model.retryCamera()
        await model.waitForQueuedConfigures()
        #expect(model.isCameraStopped)
    }

    @Test func cameraRestrictedIsRestrictedAccess() throws {
        let model = try simulator("cameraRestricted")
        #expect(model.phase == .cameraRestricted); #expect(model.access.camera == .restricted)
        #expect(!model.isCameraStopped); #expect(!model.canOpenRecordSettings)
    }

    @Test func sweepWarningMarksTheCurrentVideoSelectionAsFailed() throws {
        let model = try simulator("sweepWarning")
        #expect(model.sweepCaption == FailedCombinations.caption)
        #expect(model.hasCamera)
        #expect(try simulator("sweepWarning", mode: "photo").sweepCaption == nil)
        #expect(try simulator("pressure").sweepCaption == nil)
    }
}
