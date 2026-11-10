import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct SavedSelectionsTests {
    let uhd = Resolution.named(width: 3840, height: 2160)

    @Test func selectionsRoundTripThroughARelaunch() throws {
        let defaults = try Fixture.freshDefaults(), caps = try Fixture.load()
        let first = CameraModel(config: LaunchConfig(), capabilities: caps, isSimulator: true, defaults: defaults)
        first.mode = .photo; first.selectLens("ultraWide")
        first.record = RecordSelection(family: .h264, quality: "Low", resolution: .named(width: 1920, height: 1080), frameRate: 25, colour: .rec709)
        let second = CameraModel(config: LaunchConfig(), capabilities: caps, isSimulator: true, defaults: defaults)
        #expect(second.mode == .photo); #expect(second.lensID == "ultraWide"); #expect(second.record == first.record)
        #expect(SavedSelections.load(from: defaults)?.record == first.record)
    }

    @Test func staleSelectionMovesToNearestValid() throws {
        let defaults = try Fixture.freshDefaults()
        SavedSelections(mode: .video, lensID: "wide", record: RecordSelection(family: .raw, quality: "ProRes RAW", resolution: uhd, frameRate: 30, colour: .rec709),
                        photo: PhotoSelection(format: .raw, megapixels: 48)).save(to: defaults)
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: defaults)
        #expect(model.record == RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .rec709))
    }

    @Test func scriptedLaunchNeitherRestoresNorSaves() throws {
        let defaults = try Fixture.freshDefaults()
        let saved = SavedSelections(mode: .video, lensID: "outer", record: RecordSelection(family: .h264, quality: "Low", resolution: .named(width: 1920, height: 1080), frameRate: 25, colour: .rec709), photo: PhotoSelection(format: .heif, megapixels: 12))
        saved.save(to: defaults)
        let model = CameraModel(config: .parse(["app", "-mode", "photo"]), capabilities: try Fixture.load(), isSimulator: true, defaults: defaults)
        #expect(model.lensID == "wide"); model.selectLens("ultraWide")
        #expect(SavedSelections.load(from: defaults) == saved)
    }
}
