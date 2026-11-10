import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct LookHonestyTests {
    @Test func theLookIsNamedOnlyWhereItApplies() throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        #expect(model.lookChipID == "none"); #expect(model.summaryLookName == nil); #expect(model.viewfinderLook == nil); #expect(!model.needsFrames)
        model.mode = .photo; model.selectLook(look.id)
        #expect(model.summaryLookName == "Warm fade"); #expect(model.lookReason == nil)
        model.framesUnavailable()
        #expect(model.summaryLookName == "Warm fade")          // photo: still applied at capture
        model.selectLook(nil)
        #expect(model.notice == nil); #expect(model.summaryLookName == nil); #expect(!model.needsFrames)
    }
}
