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
    @Test func messagesSayWhatHappenedToEveryGroup() {
        func message(_ action: LookChange.Action, _ photos: Int, _ clips: Int, _ newer: Int, _ failed: Int) -> String {
            LookChange(action: action, photosChanged: photos, clipsSkipped: clips, newerSkipped: newer, photosFailed: failed).message
        }
        let newer1 = "1 photo was edited by a newer version of OpenCam and was skipped."
        let newer2 = "2 photos were edited by a newer version of OpenCam and were skipped."
        #expect(message(.applied, 0, 0, 0, 1) == "No photos were changed. 1 photo could not be changed.")
        #expect(message(.removed, 0, 0, 0, 3) == "No photos were changed. 3 photos could not be changed.")
        #expect(message(.applied, 1, 0, 0, 1) == "Applied to 1 photo. 1 photo could not be changed.")
        #expect(message(.removed, 2, 0, 0, 2) == "Look removed from 2 photos. 2 photos could not be changed.")
        #expect(message(.applied, 1, 1, 0, 1) == "Applied to 1 photo. 1 video was skipped. 1 photo could not be changed.")
        #expect(message(.applied, 0, 0, 2, 0) == "No photos were changed. " + newer2)
        #expect(message(.removed, 1, 0, 1, 0) == "Look removed from 1 photo. " + newer1)
        #expect(message(.applied, 0, 0, 1, 2) == "No photos were changed. " + newer1 + " 2 photos could not be changed.")
        #expect(message(.applied, 3, 2, 2, 2) == "Applied to 3 photos. 2 videos were skipped. " + newer2 + " 2 photos could not be changed.")
        #expect(message(.removed, 1, 1, 1, 1) == "Look removed from 1 photo. 1 video was skipped. " + newer1 + " 1 photo could not be changed.")
        #expect(message(.removed, 0, 2, 0, 0) == "No photos were changed. 2 videos were skipped.")
    }
    @Test func confirmationCountsAndTitles() {
        let clip: PhotoEdit? = nil, unedited: PhotoEdit? = PhotoEdit()
        let edited: PhotoEdit? = PhotoEdit(adjustments: Adjustments().setting(.exposure, to: 1))
        let looked: PhotoEdit? = PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade")
        var newerEdit = PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Old"); newerEdit.version = PhotoEdit.currentVersion + 1
        let newer: PhotoEdit? = newerEdit
        // Remove look changes only photos whose edit names a look and is not from a newer version.
        #expect(LookChange.photosToRemove(in: []) == 0); #expect(LookChange.photosToRemove(in: [clip, unedited, edited, newer]) == 0)
        #expect(LookChange.photosToRemove(in: [clip, looked, edited, newer]) == 1); #expect(LookChange.photosToRemove(in: [looked, looked, unedited, clip]) == 2)
        // Apply look replaces the edit of every photo that has one and is not from a newer version.
        #expect(LookChange.editsToReplace(in: []) == 0); #expect(LookChange.editsToReplace(in: [clip, unedited, newer]) == 0)
        #expect(LookChange.editsToReplace(in: [clip, unedited, edited, newer]) == 1); #expect(LookChange.editsToReplace(in: [edited, looked, unedited, clip, newer]) == 2)
        #expect(LibraryCopy.removeLookTitle(count: 1) == "Remove look from 1 photo?"); #expect(LibraryCopy.removeLookTitle(count: 4) == "Remove look from 4 photos?")
        #expect(LibraryCopy.replaceEditsTitle(count: 1) == "Replace edits on 1 photo?"); #expect(LibraryCopy.replaceEditsTitle(count: 3) == "Replace edits on 3 photos?")
        #expect(LibraryCopy.removeLookMessage == "Their edits are cleared. The original photos are not changed.")
        #expect(LibraryCopy.replaceEditsMessage == "Their current edits are replaced by this look.")
    }
    @Test func storeGivesEachItemsEditForTheCounts() throws {
        let (store, _) = try setUp()   // OC_0004.MOV, OC_0003 (edited), OC_0002, OC_0001
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        _ = try store.applyLook(look, to: store.items.filter { $0.stem == "OC_0001" })
        let edits = store.lookEdits(for: store.items)
        #expect(edits.count == 4); #expect(edits[0] == nil)
        #expect(LookChange.photosToRemove(in: edits) == 1); #expect(LookChange.editsToReplace(in: edits) == 2)
    }
    @Test func aPhotoThatCannotBeChangedIsCountedAndTheRestStillChange() throws {
        let (store, dir) = try setUp()
        // A folder where OC_0001's edit file would go makes its save fail.
        try FileManager.default.createDirectory(at: dir.appending(path: "OC_0001.edit.json"), withIntermediateDirectories: false)
        store.reload()
        let look = try store.lookStore.save(name: "Warm fade", adjustments: LookSeeder.warmFade)
        do throws(LibraryError) {
            _ = try store.applyLook(look, to: store.items.filter { $0.stem != "OC_0003" })
            Issue.record("the failed photo must be reported")
        } catch {
            guard case .lookChangeIncomplete(let change, _) = error else { Issue.record("unexpected \(error)"); return }
            #expect(change == LookChange(action: .applied, photosChanged: 1, clipsSkipped: 1, newerSkipped: 0, photosFailed: 1))
            #expect(change.message == "Applied to 1 photo. 1 video was skipped. 1 photo could not be changed.")
            #expect(error.description.hasPrefix("[LibraryStore:applyLook]"))
        }
        #expect(try EditStore(directory: dir).load(stem: "OC_0002") == PhotoEdit(adjustments: LookSeeder.warmFade, lookName: "Warm fade"))
    }
    @Test func eachFailureNamesItsFunction() {
        #expect(LibraryError.editFailed(stem: "OC_0001", reason: "r").description.hasPrefix("[LibraryStore:delete]"))
        let removed = LookChange(action: .removed, photosChanged: 0, clipsSkipped: 0, newerSkipped: 0, photosFailed: 1)
        #expect(LibraryError.lookChangeIncomplete(change: removed, reason: "r").description.hasPrefix("[LibraryStore:removeLook]"))
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
