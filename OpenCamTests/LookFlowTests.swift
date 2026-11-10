import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct LookFlowTests {
    @Test func savingAndApplyingALookCopiesItsValues() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.temperature = 30; model.adjustments.grain = 10
        let look = try model.saveAsLook(named: "  Golden ")
        #expect(look.name == "Golden"); #expect(model.looks.map(\.name) == ["Golden"])
        model.resetAll(); model.applyLook(look)
        #expect(model.adjustments == look.adjustments); #expect(model.lookName == "Golden")
        model.applyLook(nil); #expect(model.adjustments.isIdentity); #expect(model.lookName == nil)
        #expect(throws: LookStoreError.emptyName) { try model.saveAsLook(named: " ") }
    }
    @Test func renameDuplicateDeleteUpdateTheList() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        let look = try model.saveAsLook(named: "Golden"); model.applyLook(look)
        try model.renameLook(look.id, to: "Gold"); try model.duplicateLook(look.id)
        #expect(model.looks.map(\.name) == ["Gold", "Gold copy"])
        try model.deleteLook(look.id)
        #expect(model.looks.map(\.name) == ["Gold copy"]); #expect(model.lookName == "Golden"); #expect(model.adjustments == look.adjustments)
    }
    @Test func lookPreviewIsSmall() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 1200, height: 800)
        let image = try #require(await model.lookPreview(Look(id: UUID(), name: "A", adjustments: LookSeeder.warmFade, createdAt: .now)))
        #expect(max(image.width, image.height) == 240)
    }
    @Test func deletingALookKeepsTheEditThatCameFromIt() async throws {   // Review Focus 3, at the editor
        let (model, dir, looks) = try await EditorFixture.make(width: 400, height: 300)
        let look = try looks.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        model.applyLook(look); await model.waitForPreview()
        let rendered = try #require(model.renderedAdjustments); let renders = model.previewRenderCount
        try model.deleteLook(look.id)
        #expect(model.looks.isEmpty); #expect(model.adjustments == LookSeeder.warmFade); #expect(model.lookName == "Warm fade")
        await model.waitForPreview()
        #expect(model.renderedAdjustments == rendered); #expect(model.previewRenderCount == renders)   // nothing re-rendered
        #expect(model.save())
        let expected = PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade")
        #expect(try EditStore(directory: dir).load(stem: "OC_0001") == expected)
        let reopened = EditorModel(item: model.item, edits: EditStore(directory: dir), looks: looks)
        await reopened.load()
        #expect(reopened.phase == .ready); #expect(reopened.renderedAdjustments == LookSeeder.warmFade); #expect(reopened.lookName == "Warm fade")
    }
    @Test func namingSavesANewLookOrRenamesTheLookItWasOpenedFor() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.contrast = 20
        try model.saveLookName("  Golden ", renaming: nil)
        let golden = try #require(model.looks.first)
        #expect(model.looks.map(\.name) == ["Golden"]); #expect(golden.adjustments.contrast == 20); #expect(model.lookName == "Golden")
        model.adjustments.contrast = 50
        try model.saveLookName("Gold", renaming: golden)
        #expect(model.looks.count == 1); #expect(model.looks.first?.id == golden.id); #expect(model.looks.first?.name == "Gold")
        #expect(model.looks.first?.adjustments.contrast == 20)   // renaming keeps the look's values
        #expect(throws: LookStoreError.emptyName) { try model.saveLookName("  ", renaming: golden) }
        #expect(throws: LookStoreError.nameTooLong(count: 41)) { try model.saveLookName(String(repeating: "a", count: 41), renaming: nil) }
        #expect(model.looks.map(\.name) == ["Gold"])
    }
    @Test func seedLookOnce() throws {
        let store = try LookStore(directory: TestFiles.directory())
        #expect(try LookSeeder.seedWarmFade(into: store)?.name == "Warm fade"); #expect(try LookSeeder.seedWarmFade(into: store) == nil)
        #expect(store.all().count == 1); #expect(store.all().first?.adjustments == LookSeeder.warmFade)
    }
}
