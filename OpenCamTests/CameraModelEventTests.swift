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
}
