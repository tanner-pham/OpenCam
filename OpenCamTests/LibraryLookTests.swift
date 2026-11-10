import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct LibraryLookTests {
    func setUp() throws -> (LibraryStore, URL) {
        let dir = try TestFiles.directory()
        for name in ["OC_0001.JPG", "OC_0002.JPG", "OC_0003.JPG", "OC_0004.MOV"] { try Data("x".utf8).write(to: dir.appending(path: name)) }
        try EditStore(directory: dir).save(PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1)), stem: "OC_0003")
        let store = try LibraryStoreTests.make(dir); store.reload()
        return (store, dir)
    }
    @Test func applyToManyAndRemove() throws {
        let (store, dir) = try setUp()
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let applied = try store.applyLook(look, to: store.items.filter { $0.stem != "OC_0003" })   // OC_0004.MOV, OC_0002, OC_0001
        #expect(applied == LookChange(action: .applied, photosChanged: 2, clipsSkipped: 1, newerSkipped: 0)); #expect(applied.message == "Applied to 2 photos. 1 video was skipped.")
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "OC_0004.edit.json").path(percentEncoded: false)))
        let edits = EditStore(directory: dir), expected = PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade")
        #expect(try edits.load(stem: "OC_0001") == expected); #expect(try edits.load(stem: "OC_0002") == expected)
        #expect(store.edit(for: try #require(store.items.first { $0.stem == "OC_0001" })) == expected)   // the store reloaded
        let removed = try store.removeLook(from: store.items)
        #expect(removed.message == "Look removed from 2 photos. 1 video was skipped.")
        #expect(try edits.load(stem: "OC_0001") == PhotoEdit()); #expect(try edits.load(stem: "OC_0003").adjustments.exposure == 1)
    }
    @Test func messagesForEveryCount() {
        func message(_ action: LookChange.Action, _ photos: Int, _ clips: Int, _ newer: Int) -> String {
            LookChange(action: action, photosChanged: photos, clipsSkipped: clips, newerSkipped: newer).message
        }
        #expect(message(.applied, 0, 0, 0) == "No photos were changed."); #expect(message(.removed, 0, 0, 0) == "No photos were changed.")
        #expect(message(.applied, 1, 0, 0) == "Applied to 1 photo."); #expect(message(.applied, 3, 0, 0) == "Applied to 3 photos.")
        #expect(message(.removed, 1, 0, 0) == "Look removed from 1 photo."); #expect(message(.removed, 3, 0, 0) == "Look removed from 3 photos.")
        #expect(message(.applied, 0, 1, 0) == "No photos were changed. 1 video was skipped.")
        #expect(message(.applied, 2, 2, 0) == "Applied to 2 photos. 2 videos were skipped.")
        #expect(message(.applied, 1, 0, 1) == "Applied to 1 photo. 1 photo was edited by a newer version of OpenCam and was skipped.")
        #expect(message(.removed, 0, 1, 2) == "No photos were changed. 1 video was skipped. 2 photos were edited by a newer version of OpenCam and were skipped.")
    }
    @Test func newerEditsAreSkippedAndUntouched() throws {
        let (store, dir) = try setUp()
        let newer = Data(#"{"version": 99, "lookName": "Old", "adjustments": {"exposure": 2}}"#.utf8), editURL = dir.appending(path: "OC_0002.edit.json")
        try newer.write(to: editURL); store.reload()
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let photos = store.items.filter { $0.stem == "OC_0001" || $0.stem == "OC_0002" }
        #expect(try store.applyLook(look, to: photos) == LookChange(action: .applied, photosChanged: 1, clipsSkipped: 0, newerSkipped: 1))
        #expect(try store.removeLook(from: store.items.filter { $0.stem == "OC_0002" }) == LookChange(action: .removed, photosChanged: 0, clipsSkipped: 0, newerSkipped: 1))
        #expect(try Data(contentsOf: editURL) == newer)
    }
    @Test func deletingALookKeepsPhotosThatUsedIt() throws {   // Review Focus 3
        let (store, dir) = try setUp()
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        let item = try #require(store.items.first { $0.stem == "OC_0001" })
        _ = try store.applyLook(look, to: [item])
        _ = try store.lookStore.rename(look.id, to: "Cool"); try store.lookStore.delete(look.id); store.reload()
        #expect(store.looks.isEmpty)
        #expect(store.edit(for: item) == PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade"))
        #expect(try EditStore(directory: dir).load(stem: "OC_0001") == PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade"))
    }
}
