import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct SessionConfigurationTests {
    @Test func configurationFollowsTheSelection() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        model.selectLens("ultraWide"); model.mode = .video
        let config = try #require(model.sessionConfiguration)
        #expect(config.lens.id == "ultraWide"); #expect(config.mode == .video)
        #expect(config.video == model.currentVideoOption); #expect(config.photo == model.currentPhotoOption)
    }
}
