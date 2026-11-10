import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct CameraLookTests {
    let warm = Adjustments().setting(.temperature, to: 20)
    let cool = Adjustments().setting(.temperature, to: -20)

    func make(_ defaults: UserDefaults, _ looks: LookStore?, _ args: [String] = []) throws -> CameraModel {
        CameraModel(config: args.isEmpty ? LaunchConfig() : .parse(["app"] + args), capabilities: try Fixture.load(), isSimulator: true,
                    defaults: defaults, lookStore: looks)
    }

    @Test func noneByDefaultAndTheChoiceSurvivesARelaunch() throws {
        let defaults = try Fixture.freshDefaults(), looks = try LookStore(directory: TestFiles.directory())
        let look = try looks.save(name: "Warm fade", adjustments: warm)
        let first = try make(defaults, looks)
        #expect(first.cameraLook == nil); #expect(first.looks.map(\.id) == [look.id])
        first.selectLook(look.id)
        #expect(first.cameraLook == CameraLook(look))
        let second = try make(defaults, looks)
        #expect(second.cameraLook == CameraLook(look)); #expect(SavedSelections.load(from: defaults)?.look?.id == look.id)
        second.selectLook(nil)
        #expect(try make(defaults, looks).cameraLook == nil)
        second.selectLook(UUID()); #expect(second.cameraLook == nil)
    }

    @Test func deletedLookBecomesNoneAndARenamedLookTakesItsNewName() throws {   // Review Focus 1
        let defaults = try Fixture.freshDefaults(), looks = try LookStore(directory: TestFiles.directory())
        let a = try looks.save(name: "Warm fade", adjustments: warm), b = try looks.save(name: "Cool", adjustments: cool)
        let model = try make(defaults, looks)
        model.selectLook(a.id)
        _ = try looks.rename(a.id, to: "Warm"); model.reloadLooks()
        #expect(model.cameraLook == CameraLook(id: a.id, name: "Warm", adjustments: warm))
        #expect(SavedSelections.load(from: defaults)?.look?.name == "Warm")
        try looks.delete(a.id); model.reloadLooks()
        #expect(model.cameraLook == nil); #expect(model.looks.map(\.id) == [b.id]); #expect(SavedSelections.load(from: defaults)?.look == nil)
        model.selectLook(b.id); try looks.delete(b.id)
        #expect(try make(defaults, looks).cameraLook == nil)            // gone before the next launch
        #expect(try make(defaults, nil).cameraLook == nil)              // no look store at all
    }

    @Test func reconciledTakesTheLooksCurrentValues() {
        let id = UUID(), now = Date.now
        let selected = CameraLook(id: id, name: "Warm fade", adjustments: warm)
        #expect(CameraLook.reconciled(selected, with: [Look(id: id, name: "Warm fade", adjustments: cool, createdAt: now)])
                == CameraLook(id: id, name: "Warm fade", adjustments: cool))
        #expect(CameraLook.reconciled(selected, with: [Look(id: UUID(), name: "Warm fade", adjustments: warm, createdAt: now)]) == nil)
        #expect(CameraLook.reconciled(nil, with: []) == nil)
    }

    @Test func closingTheLibraryReadsTheLooksAgain() async throws {
        let looks = try LookStore(directory: TestFiles.directory())
        let a = try looks.save(name: "Warm fade", adjustments: warm)
        let model = try make(try Fixture.freshDefaults(), looks)
        model.selectLook(a.id); model.openLibrary()
        let added = try looks.save(name: "Agfa", adjustments: cool); try looks.delete(a.id)
        model.isLibraryPresented = false
        await model.closeLibrary()
        #expect(model.cameraLook == nil); #expect(model.looks.map(\.id) == [added.id])
    }

    @Test func scriptedLaunchSelectsByNameAndNeitherRestoresNorSaves() throws {
        let defaults = try Fixture.freshDefaults(), looks = try LookStore(directory: TestFiles.directory())
        let a = try looks.save(name: "Warm fade", adjustments: warm), b = try looks.save(name: "Cool", adjustments: cool)
        try make(defaults, looks).selectLook(b.id)
        let scripted = try make(defaults, looks, ["-cameraLook", "Warm fade"])
        #expect(scripted.cameraLook?.id == a.id)
        scripted.selectLook(nil)
        #expect(SavedSelections.load(from: defaults)?.look?.id == b.id)
        #expect(try make(defaults, looks, ["-mode", "photo"]).cameraLook == nil)
        #expect(try make(defaults, looks, ["-cameraLook", "Missing"]).cameraLook == nil)
    }

    @Test func savedSelectionsWithoutALookStillDecode() throws {
        let defaults = try Fixture.freshDefaults()
        let old = SavedSelections(mode: .photo, lensID: "wide", record: RecordSelection(family: .hevc, quality: "High", resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709),
                                  photo: PhotoSelection(format: .heif, megapixels: 12))
        old.save(to: defaults)
        #expect(SavedSelections.load(from: defaults) == old); #expect(SavedSelections.load(from: defaults)?.look == nil)
    }
}
