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

    @Test func failedReconfigureKeepsTheLastWorkingSelection() async throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        model.phase = .ready
        let working = try #require(model.sessionConfiguration)
        let fake = FakeSessionConfigurator(failingLensIDs: ["ultraWide"])
        model.attachSession(fake, configuredWith: working)
        let lensID = model.lensID, record = model.record, photo = model.photo

        model.selectLens("ultraWide")
        await #expect(throws: CameraSessionError.self) { try await model.applySelection() }
        #expect(model.phase == .ready); #expect(model.notice == "That format could not be used.")
        #expect(model.lensID == lensID); #expect(model.record == record); #expect(model.photo == photo)
        #expect(model.sessionConfiguration == working)

        model.selectLens("wide@2")
        try await model.applySelection()
        #expect(model.lensID == "wide@2"); #expect(model.notice == nil)
        #expect(await fake.applied.map(\.lens.id) == ["wide@2"])
    }
}
