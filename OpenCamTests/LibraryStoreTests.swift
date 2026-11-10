import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct LibraryStoreTests {
    static func make(_ dir: URL) throws -> LibraryStore {
        LibraryStore(captures: try CaptureStore(directory: dir), edits: EditStore(directory: dir),
                     looks: try LookStore(directory: TestFiles.directory()), thumbnails: ThumbnailCache(directory: try TestFiles.directory()))
    }
    @Test func reloadListsItemsAndDeleteRemovesOriginalsEditsAndSidecars() async throws {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.DNG", "OC_0001.HEIC", "OC_0002.JPG", "OC_0003.MOV", "OC_0003.json"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)), stem: "OC_0001")
        let store = try Self.make(dir); store.reload()
        #expect(store.items.map(\.id) == ["OC_0003.MOV", "OC_0002", "OC_0001"])
        guard case .failed = await store.thumbnail(for: store.items[1]) else { Issue.record("an undecodable picture must give .failed"); return }
        guard case .failed = await store.thumbnail(for: store.items[0]) else { Issue.record("an undecodable clip must give .failed"); return }
        #expect(store.edit(for: store.items[2]).adjustments.exposure == 1); #expect(store.edit(for: store.items[0]) == PhotoEdit())
        try store.delete([store.items[0], store.items[2]])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)) == ["OC_0002.JPG"])
        #expect(store.items.map(\.id) == ["OC_0002"])
    }
    @Test func deleteKeepsAPhotoWhoseEditIsNewer() throws {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.JPG", "OC_0002.JPG"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        let newer = Data(#"{"version": 99, "adjustments": {"exposure": 1}}"#.utf8), editURL = dir.appending(path: "OC_0002.edit.json")
        try newer.write(to: editURL)
        let store = try Self.make(dir); store.reload()
        #expect(throws: LibraryError.newerEdit(path: editURL.path(percentEncoded: false), version: 99)) { try store.delete(store.items) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == ["OC_0002.JPG", "OC_0002.edit.json"])
        #expect(try Data(contentsOf: editURL) == newer); #expect(store.items.map(\.id) == ["OC_0002"])
    }
}
