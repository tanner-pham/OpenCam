import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct EditorExportTests {
    @Test func exportFromTheEditorAndAfterTheOriginalIsGone() async throws {
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        model.adjustments.saturation = -100
        let url = try #require(await model.export())
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false))); #expect(model.alertMessage == nil)
        try FileManager.default.removeItem(at: dir.appending(path: "OC_0001.JPG"))
        #expect(await model.export() == nil); #expect(model.phase == .failed("This photo could not be opened."))
    }

    /// Export renders what the editor shows, unsaved changes included, and writes nothing beside the original.
    @Test func exportUsesTheUnsavedEditAndLeavesCapturesAlone() async throws {
        let (model, dir, _) = try await EditorFixture.make(width: 400, height: 300)
        let before = try TestFiles.snapshot(dir)
        model.adjustments.exposure = 1
        let url = try #require(await model.export())
        #expect(abs(try PixelReader.rgb(PictureDecoder.full(at: url), x: 200, y: 150).x - 0.686) < 0.02)
        #expect(model.hasUnsavedChanges); #expect(!model.isExporting)
        #expect(try TestFiles.snapshot(dir) == before)
    }

    /// An encoder that fails part way leaves no partial file in the export folder, and the editor says the export failed.
    @Test func aFailedWriteLeavesNoPartialFile() async throws {
        let captures = try TestFiles.directory(), out = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let exporter = PhotoExporter(directory: out) { _, url, _ in
            try Data("half a picture".utf8).write(to: url)
            throw TestFileError.bitmapUnavailable
        }
        let model = EditorModel(item: item, edits: EditStore(directory: captures), looks: try LookStore(directory: TestFiles.directory()),
                                exporter: exporter)
        await model.load()
        model.adjustments.exposure = 1
        #expect(await model.export() == nil)
        #expect(model.alertMessage == "The photo could not be exported."); #expect(model.phase == .ready)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path(percentEncoded: false)).isEmpty)
    }

    @Test func discardExportRemovesTheFile() async throws {
        let (model, _, _) = try await EditorFixture.make(width: 40, height: 30)
        let url = try #require(await model.export())
        model.discardExport(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    /// A photo edited by a newer version opens read-only; exporting it would drop what this version cannot read.
    @Test func aReadOnlyPhotoDoesNotExport() async throws {
        let captures = try TestFiles.directory()
        _ = try TestFiles.writeJPEG(width: 40, height: 30, rgb: SIMD3(0.5, 0.5, 0.5), to: captures.appending(path: "OC_0001.JPG"))
        try Data(#"{"version": 3, "adjustments": {"exposure": 1}}"#.utf8).write(to: captures.appending(path: "OC_0001.edit.json"))
        let item = try #require(LibraryScanner.items(in: captures).first)
        let model = EditorModel(item: item, edits: EditStore(directory: captures), looks: try LookStore(directory: TestFiles.directory()))
        await model.load()
        #expect(model.phase == .failed(LibraryCopy.newerEdit))
        #expect(!model.canExport)
        #expect(await model.export() == nil); #expect(model.alertMessage == nil); #expect(model.phase == .failed(LibraryCopy.newerEdit))
    }
}
