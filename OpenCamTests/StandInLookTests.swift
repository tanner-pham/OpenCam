import CoreImage
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct StandInLookTests {
    @Test func warmFadeWarmsTheStandInAtTheSameSize() async throws {
        let plain = try #require(StandInPicture.base(size: CGSize(width: 200, height: 300), scale: 1))
        let look = CameraLook(id: UUID(), name: "Warm fade", adjustments: LookSeeder.warmFade)
        let looked = try #require(await StandInPicture.looked(plain, look: look))
        #expect(looked.width == plain.width); #expect(looked.height == plain.height)
        #expect(looked.colorSpace?.name == CGColorSpace.displayP3)
        // Core Image rows count from the bottom: y 250 is the blue sky near the top.
        let p = try PixelReader.rgb(CIImage(cgImage: plain), x: 100, y: 250), l = try PixelReader.rgb(CIImage(cgImage: looked), x: 100, y: 250)
        #expect(l.x - l.z > p.x - p.z + 0.03)
    }

    @Test func viewfinderLookFollowsTheSelection() throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        #expect(model.viewfinderLook == nil)
        model.selectLook(look.id); #expect(model.viewfinderLook == CameraLook(look))
        model.selectLook(nil); #expect(model.viewfinderLook == nil)
    }
}
