import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct LookRuleTests {
    let uhd = Resolution.named(width: 3840, height: 2160)

    func make() throws -> (CameraModel, LookStore, Look) {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        return (model, looks, look)
    }

    @Test func changingToHLGTurnsTheLookOffWithItsNotice() throws {
        let (model, _, look) = try make()
        model.mode = .video
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .rec709)
        model.selectLook(look.id)
        #expect(model.lookReason == "Shown in the viewfinder only. Video is recorded without it."); #expect(model.summaryParts.last == "Warm fade")
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .hlg)
        #expect(model.currentVideoOption?.colour == .hlg)
        #expect(model.cameraLook == nil); #expect(model.notice == "Look turned off. Looks need Rec. 709 or P3.")
        #expect(model.lookChipID == "none"); #expect(model.lookChips.dropFirst().allSatisfy { !$0.isAvailable })
        #expect(model.lookReason == "Looks need Rec. 709 or P3."); #expect(model.summaryParts == ["ProRes", "4K", "HLG"])
        model.mode = .photo
        model.selectLook(chipID: look.id.uuidString)
        #expect(model.cameraLook?.id == look.id); #expect(model.notice == nil); #expect(model.lookReason == nil)
        model.mode = .video
        #expect(model.cameraLook == nil); #expect(model.notice == "Look turned off. Looks need Rec. 709 or P3.")
    }

    @Test func deletedLookLeavesNoNameInTheSummary() throws {
        let (model, looks, look) = try make()
        model.mode = .photo; model.selectLook(look.id)
        #expect(model.summaryParts == ["RAW + HEIF", "48 MP", "Warm fade"])
        try looks.delete(look.id); model.reloadLooks()
        #expect(model.summaryLookName == nil); #expect(model.summaryParts == ["RAW + HEIF", "48 MP"]); #expect(model.lookChips.map(\.title) == ["None"])
    }

    @Test func noCameraPictureNamesNoLook() throws {
        let looks = try LookStore(directory: TestFiles.directory())
        _ = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let scanning = CameraModel(config: .parse(["app", "-state", "scanning", "-cameraLook", "Warm fade"]), capabilities: try Fixture.load(),
                                   isSimulator: true, defaults: try Fixture.freshDefaults(), lookStore: looks)
        #expect(scanning.cameraLook != nil); #expect(scanning.summaryLookName == nil); #expect(scanning.summaryParts == ["--"])
    }

    /// A look chosen in photo mode whose configure fails, so the selection goes back to the last working HLG video one.
    @Test func failedConfigureThatRestoresHLGTurnsTheLookOff() async throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: Adjustments().setting(.temperature, to: 20))
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                captureStore: try CaptureStore(directory: TestFiles.directory()), lookStore: looks)
        model.phase = .ready
        model.mode = .video
        model.record = RecordSelection(family: .proRes, quality: "422 HQ", resolution: uhd, frameRate: 30, colour: .hlg)
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        await fake.setFailingLensIDs([model.lensID])
        model.mode = .photo
        model.selectLook(look.id)
        #expect(model.cameraLook != nil)
        try? await model.applySelection()
        #expect(model.mode == .video); #expect(model.record.colour == .hlg)
        #expect(model.cameraLook == nil); #expect(model.notice == "Look turned off. Looks need Rec. 709 or P3.")
    }
}
