import Foundation
import Testing
@testable import OpenCam

/// An edit file this build cannot read, for whatever reason, is never overwritten or removed, and each path says so.
@MainActor @Suite struct UnreadableEditTests {
    static let garbage = Data([0xFF, 0x00, 0x7B, 0x22, 0x01, 0xFE])
    /// From a newer build whose shape this one does not know: `adjustments` is no longer an object.
    static let newerShape = Data(#"{"version": 7, "adjustments": [{"key": "exposure", "value": 1}], "lookName": {"id": 3}}"#.utf8)

    /// OC_0001 has a garbage edit, OC_0002 a newer edit of unknown shape, OC_0003 a plain edit with a look, OC_0004 none.
    func setUp() throws -> (LibraryStore, URL) {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.JPG", "OC_0002.JPG", "OC_0003.JPG", "OC_0004.JPG"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        try Self.garbage.write(to: dir.appending(path: "OC_0001.edit.json"))
        try Self.newerShape.write(to: dir.appending(path: "OC_0002.edit.json"))
        try EditStore(directory: dir).save(PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade"), stem: "OC_0003")
        let store = try LibraryStoreTests.make(dir); store.reload()
        return (store, dir)
    }

    func expectUnchanged(_ dir: URL) throws {
        #expect(try Data(contentsOf: dir.appending(path: "OC_0001.edit.json")) == Self.garbage)
        #expect(try Data(contentsOf: dir.appending(path: "OC_0002.edit.json")) == Self.newerShape)
    }

    @Test func theStoreRefusesToSaveOrRemoveEither() throws {
        let dir = try TestFiles.directory()
        try Self.garbage.write(to: dir.appending(path: "OC_0001.edit.json"))
        try Self.newerShape.write(to: dir.appending(path: "OC_0002.edit.json"))
        let store = EditStore(directory: dir)
        let edit = PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1))
        let garbagePath = store.url(forStem: "OC_0001").path(percentEncoded: false)
        let newerPath = store.url(forStem: "OC_0002").path(percentEncoded: false)
        for stem in ["OC_0001", "OC_0002"] {
            #expect(throws: EditStoreError.self) { try store.save(edit, stem: stem) }
            #expect(throws: EditStoreError.self) { try store.save(PhotoEdit(), stem: stem) }
            #expect(throws: EditStoreError.self) { try store.remove(stem: stem) }
        }
        do throws(EditStoreError) { _ = try store.save(edit, stem: "OC_0001"); Issue.record("must refuse") } catch {
            guard case .unreadable(let path, _) = error else { Issue.record("unexpected \(error)"); return }
            #expect(path == garbagePath)
        }
        #expect(throws: EditStoreError.newerVersion(path: newerPath, version: 7)) { try store.save(edit, stem: "OC_0002") }
        #expect(throws: EditStoreError.newerVersion(path: newerPath, version: 7)) { try store.load(stem: "OC_0002") }
        do throws(EditStoreError) { _ = try store.load(stem: "OC_0001"); Issue.record("must not load") } catch {
            guard case .unreadable = error else { Issue.record("unexpected \(error)"); return }
        }
        try expectUnchanged(dir)
    }

    /// The confirmation counts agree with the action: a photo whose edit could not be loaded will be reported as "could not be
    /// changed", so it is neither one Remove look changes nor one whose edit Apply look replaces.
    @Test func theConfirmationCountsLeaveThemOut() throws {
        let (store, _) = try setUp()   // OC_0004 (no edit), OC_0003 (look), OC_0002 (newer shape), OC_0001 (garbage)
        let edits = store.lookEdits(for: store.items)
        #expect(edits.count == 4); #expect(edits[2] == nil); #expect(edits[3] == nil)
        #expect(LookChange.photosToRemove(in: edits) == 1); #expect(LookChange.editsToReplace(in: edits) == 1)
        let unreadable = store.lookEdits(for: store.items.filter { $0.stem == "OC_0001" || $0.stem == "OC_0002" })
        #expect(LookChange.photosToRemove(in: unreadable) == 0); #expect(LookChange.editsToReplace(in: unreadable) == 0)
    }

    @Test func applyLookCountsThemAndLeavesThemWhole() throws {
        let (store, dir) = try setUp()
        let look = try store.lookStore.save(name: "Cool", adjustments: Adjustments().setting(.temperature, to: -20))
        do throws(LibraryError) {
            _ = try store.applyLook(look, to: store.items)
            Issue.record("the unreadable photo must be reported")
        } catch {
            guard case .lookChangeIncomplete(let change, _) = error else { Issue.record("unexpected \(error)"); return }
            #expect(change == LookChange(action: .applied, photosChanged: 2, clipsSkipped: 0, newerSkipped: 1, photosFailed: 1))
        }
        try expectUnchanged(dir)
    }

    @Test func removeLookCountsThemAndLeavesThemWhole() throws {
        let (store, dir) = try setUp()
        do throws(LibraryError) {
            _ = try store.removeLook(from: store.items)
            Issue.record("the unreadable photo must be reported")
        } catch {
            guard case .lookChangeIncomplete(let change, _) = error else { Issue.record("unexpected \(error)"); return }
            #expect(change == LookChange(action: .removed, photosChanged: 1, clipsSkipped: 0, newerSkipped: 1, photosFailed: 1))
            #expect(change.message == "Look removed from 1 photo. 1 photo was edited by a newer version of OpenCam and was skipped. 1 photo could not be changed.")
        }
        try expectUnchanged(dir)
    }

    @Test func deleteLeavesEachPhotoWhole() throws {
        let (store, dir) = try setUp()
        let garbageItem = try #require(store.items.first { $0.stem == "OC_0001" })
        let newerItem = try #require(store.items.first { $0.stem == "OC_0002" })
        let garbagePath = dir.appending(path: "OC_0001.edit.json").path(percentEncoded: false)
        do throws(LibraryError) { try store.delete([garbageItem]); Issue.record("must refuse") } catch {
            guard case .unreadableEdit(let path, _) = error else { Issue.record("unexpected \(error)"); return }
            #expect(path == garbagePath)
        }
        #expect(throws: LibraryError.newerEdit(path: dir.appending(path: "OC_0002.edit.json").path(percentEncoded: false), version: 7)) {
            try store.delete([newerItem])
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        #expect(Set(["OC_0001.JPG", "OC_0002.JPG"]).isSubset(of: Set(names)))
        try expectUnchanged(dir)
        #expect(LibraryCopy.unreadableEdit == "This photo's edit could not be read.")
    }

    @Test func theEditorOpensEachReadOnlyAndDoneWritesNothing() async throws {
        let (_, dir) = try setUp()
        let looks = try LookStore(directory: TestFiles.directory())
        for (stem, message) in [("OC_0001", LibraryCopy.unreadableEdit), ("OC_0002", LibraryCopy.newerEdit)] {
            let item = try #require(LibraryScanner.items(in: dir).first { $0.stem == stem })
            let model = EditorModel(item: item, edits: EditStore(directory: dir), looks: looks)
            await model.load()
            #expect(model.phase == .failed(message))
            model.adjustments.exposure = 1
            #expect(!model.save()); #expect(!model.hasUnsavedChanges)
            model.resetAll()
            #expect(!model.save())
        }
        try expectUnchanged(dir)
    }
}
