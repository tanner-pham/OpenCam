import CoreGraphics
import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct EditorModelTests {
    @Test func fortyEightMegapixelOriginalRendersOnlyTheProxy() async throws {   // Review Focus 2
        let (model, _, _) = try await EditorFixture.make(width: 8064, height: 6048)
        #expect(model.phase == .ready); #expect(model.proxySize == CGSize(width: 2048, height: 1536))
        let rendersBefore = model.previewRenderCount
        for step in 1...30 { model.adjustments.exposure = Double(step) / 10 }
        await model.waitForPreview()
        #expect(model.previewRenderCount > rendersBefore)   // the slider change really rendered
        let size = try #require(model.lastRenderPixelSize)   // measured on the CGImage the renderer returned
        #expect(max(size.width, size.height) <= 2048); #expect(size == CGSize(width: 2048, height: 1536))
        #expect(model.renderedAdjustments == model.adjustments); #expect(model.previewRenderCount <= 3)
    }
    @Test func opensWithItsSavedEdit() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.contrast, to: 25), lookName: "Warm fade"), stem: "OC_0001")
        let item = try #require(LibraryScanner.items(in: dir).first)
        let model = EditorModel(item: item, edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.adjustments.contrast == 25); #expect(model.lookName == "Warm fade"); #expect(!model.hasChanges); #expect(model.preview != nil)
    }
    @Test func resetsAndSave() async throws {
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.shadows = 40; model.adjustments.tint = -10; #expect(model.hasChanges)
        model.reset(.shadows); #expect(model.adjustments.shadows == 0); #expect(model.adjustments.tint == -10)
        #expect(model.save()); #expect(try EditStore(directory: dir).load(stem: "OC_0001").adjustments.tint == -10)
        model.resetAll(); #expect(model.adjustments.isIdentity); #expect(model.save())
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0001.edit.json").path(percentEncoded: false)))
    }
    @Test func originalRemovedWhileOpenSaysCannotOpen() async throws {   // Review Focus 5
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0001.JPG"))
        model.adjustments.exposure = 1
        await model.waitForPreview()
        #expect(!model.save()); #expect(model.phase == .failed("This photo could not be opened."))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0001.edit.json").path(percentEncoded: false)))
    }
    @Test func undecodableOriginalSaysCannotOpen() async throws {
        let dir = try TestFiles.directory()
        try Data("nope".utf8).write(to: dir.appending(path: "OC_0001.JPG"))
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed("This photo could not be opened.")); #expect(model.preview == nil)
    }
    @Test func editFromANewerVersionOpensReadOnly() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        let newer = Data(#"{"version": 99, "adjustments": {"exposure": 1}, "masks": []}"#.utf8), editURL = dir.appending(path: "OC_0001.edit.json")
        try newer.write(to: editURL)
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed("This photo was edited by a newer version of OpenCam."))
        #expect(!model.save()); #expect(try Data(contentsOf: editURL) == newer)
    }
    @Test func firstRenderThatFailsSaysCannotOpen() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir),
                                looks: try LookStore(directory: TestFiles.directory()), renderPreview: { _, _ in nil })
        await model.load()
        #expect(model.phase == .failed("This photo could not be opened.")); #expect(model.preview == nil)
    }
    @Test func unsavedChangesFollowTheOpeningValues() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.contrast, to: 25)), stem: "OC_0001")
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(!model.hasUnsavedChanges)                                   // unchanged
        model.adjustments.contrast = 40; #expect(model.hasUnsavedChanges)   // changed
        model.adjustments.contrast = 25; #expect(!model.hasUnsavedChanges)  // back to the opening value
        model.resetAll(); #expect(model.hasUnsavedChanges)                  // the opening edit was not empty
    }
    @Test func newerVersionEditHasNoUnsavedChanges() async throws {
        let dir = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 400, height: 300, rgb: SIMD3(0.5, 0.5, 0.5), to: dir.appending(path: "OC_0001.JPG"))
        try Data(#"{"version": 99, "adjustments": {"exposure": 1}}"#.utf8).write(to: dir.appending(path: "OC_0001.edit.json"))
        let model = EditorModel(item: try #require(LibraryScanner.items(in: dir).first), edits: EditStore(directory: dir), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(!model.hasUnsavedChanges)
        model.adjustments.exposure = 2; #expect(!model.hasUnsavedChanges)   // read-only: nothing can be saved, so nothing is lost
    }
}
