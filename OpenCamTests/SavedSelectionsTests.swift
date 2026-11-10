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

    // A device launch starts with no capabilities; the saved choices apply once real ones arrive.
    let empty = CaptureCapabilities(lenses: [], videoOptions: [], photoOptions: [], osBuild: "", modelIdentifier: "")
    let h264 = RecordSelection(family: .h264, quality: "Low", resolution: .named(width: 1920, height: 1080), frameRate: 25, colour: .rec709)

    @Test func savedSelectionIsRestoredWhenCapabilitiesArrive() throws {
        let defaults = try Fixture.freshDefaults()
        let saved = SavedSelections(mode: .photo, lensID: "ultraWide", record: h264, photo: PhotoSelection(format: .raw, megapixels: 12))
        saved.save(to: defaults)
        let model = CameraModel(config: LaunchConfig(), capabilities: empty, isSimulator: false, defaults: defaults)
        #expect(SavedSelections.load(from: defaults) == saved)
        model.replaceCapabilities(try Fixture.load())
        #expect(model.mode == .photo); #expect(model.lensID == "ultraWide")
        #expect(model.record == h264); #expect(model.photo == saved.photo)
        #expect(SavedSelections.load(from: defaults) == saved)
    }

    @Test func missingSavedLensFallsBackToTheDefaultLens() throws {
        let defaults = try Fixture.freshDefaults()
        SavedSelections(mode: .video, lensID: "gone", record: h264, photo: PhotoSelection(format: .heif, megapixels: 12)).save(to: defaults)
        let model = CameraModel(config: LaunchConfig(), capabilities: empty, isSimulator: false, defaults: defaults)
        model.replaceCapabilities(try Fixture.load())
        #expect(model.lensID == "wide"); #expect(model.currentVideoOption != nil); #expect(model.currentPhotoOption != nil)
        #expect(SavedSelections.load(from: defaults)?.lensID == "wide")
    }

    @Test func scriptedLaunchIgnoresSavedSelectionWhenCapabilitiesArrive() throws {
        let defaults = try Fixture.freshDefaults()
        let saved = SavedSelections(mode: .photo, lensID: "ultraWide", record: h264, photo: PhotoSelection(format: .heif, megapixels: 12))
        saved.save(to: defaults)
        let model = CameraModel(config: .parse(["app", "-mode", "video"]), capabilities: empty, isSimulator: false, defaults: defaults)
        model.replaceCapabilities(try Fixture.load())
        #expect(model.mode == .video); #expect(model.lensID == "wide"); #expect(model.record != h264)
        #expect(SavedSelections.load(from: defaults) == saved)
    }
}
