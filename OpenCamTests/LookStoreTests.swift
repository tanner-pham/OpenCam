import Foundation
import Testing
@testable import OpenCam

@Suite struct LookStoreTests {
    let warm = Adjustments().setting(.temperature, to: 20)
    let forty = String(repeating: "b", count: 40), thirtyFiveCopy = String(repeating: "b", count: 35) + " copy"
    @Test func saveListsSortedByNameAndAllowsDuplicates() throws {
        let store = try LookStore(directory: TestFiles.directory())
        _ = try store.save(name: "  warm fade ", adjustments: warm)
        _ = try store.save(name: "Agfa", adjustments: Adjustments()); _ = try store.save(name: "Agfa", adjustments: warm)
        #expect(store.all().map(\.name) == ["Agfa", "Agfa", "warm fade"]); #expect(store.all().last?.adjustments == warm)
        let saved = try #require(store.all().last)
        #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "\(saved.id.uuidString).json").path(percentEncoded: false)))
    }
    @Test func nameRules() throws {
        #expect(throws: LookStoreError.emptyName) { try LookStore.validName(" \n ") }
        #expect(throws: LookStoreError.nameTooLong(count: 41)) { try LookStore.validName(forty + "b") }
        #expect(try LookStore.validName(" " + forty + " ") == forty)
        #expect(LookStore.nameProblem(" ") == "Enter a name."); #expect(LookStore.nameProblem(forty + "b") == "Use 40 characters or fewer.")
        #expect(LookStore.nameProblem("Warm fade") == nil)
    }
    @Test func renameDuplicateDelete() throws {
        let store = try LookStore(directory: TestFiles.directory())
        let look = try store.save(name: "Warm fade", adjustments: warm)
        let renamed = try store.rename(look.id, to: "Warm"); #expect(renamed.id == look.id); #expect(renamed.adjustments == warm)
        let copy = try store.duplicate(look.id); #expect(copy.name == "Warm copy"); #expect(copy.id != look.id); #expect(copy.adjustments == warm)
        let long = try store.save(name: forty, adjustments: warm); #expect(try store.duplicate(long.id).name == thirtyFiveCopy)
        try Data("{".utf8).write(to: store.directory.appending(path: "\(UUID().uuidString).json"))
        try store.delete(look.id)
        #expect(Set(store.all().map(\.name)) == [thirtyFiveCopy, forty, "Warm copy"]); #expect(store.all().last?.name == "Warm copy")
        #expect(throws: LookStoreError.notFound(id: look.id)) { try store.rename(look.id, to: "X") }
    }
    @Test func deletingALookLeavesPhotoEditsUnchanged() throws {
        let store = try LookStore(directory: TestFiles.directory())
        let edits = EditStore(directory: try TestFiles.directory())
        let look = try store.save(name: "Warm fade", adjustments: warm)
        let edit = PhotoEdit(adjustments: look.adjustments, lookName: look.name)
        try edits.save(edit, stem: "OC_0001")
        try store.delete(look.id)
        #expect(store.all().isEmpty)
        #expect(try edits.load(stem: "OC_0001") == edit)
    }
    @Test func unreadableLookThrowsReadError() throws {
        let store = try LookStore(directory: TestFiles.directory())
        let id = UUID()
        try Data("{".utf8).write(to: store.directory.appending(path: "\(id.uuidString).json"))
        do {
            _ = try store.rename(id, to: "X")
            Issue.record("Expected an error")
        } catch {
            guard case .unreadable = error else { Issue.record("Wrong error: \(error)"); return }
            #expect(error.description.hasPrefix("[LookStore:read] Cannot read the look"))
        }
    }

    func writeLook(_ json: String, in store: LookStore, id: UUID) throws -> URL {
        let url = store.directory.appending(path: "\(id.uuidString).json"); try Data(json.utf8).write(to: url); return url }
    @Test func lookFilesFromBeforeLoadAsVersionOneAndAreStampedOnWrite() throws {
        let store = try LookStore(directory: TestFiles.directory()), id = UUID()
        let url = try writeLook(#"{"id": "\#(id.uuidString)", "name": "Old", "adjustments": {"temperature": 20}, "createdAt": "2026-11-10T09:00:00Z"}"#, in: store, id: id)
        #expect(store.all().map(\.version) == [1]); #expect(store.all().first?.adjustments == Adjustments().setting(.temperature, to: 20)); _ = try store.rename(id, to: "Older")
        #expect(try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: url)).version == 2); #expect(try store.save(name: "New", adjustments: Adjustments()).version == 2) }
    @Test func newerLookIsListedButNotRenamedOrDuplicated() throws {
        let store = try LookStore(directory: TestFiles.directory()), id = UUID()
        let json = #"{"id": "\#(id.uuidString)", "name": "Future", "version": 3, "adjustments": {"exposure": 1, "masks": []}, "createdAt": "2026-11-10T09:00:00Z"}"#
        let url = try writeLook(json, in: store, id: id), path = url.path(percentEncoded: false)
        #expect(store.all().map(\.name) == ["Future"]); #expect(throws: LookStoreError.newerVersion(path: path, version: 3)) { try store.rename(id, to: "Now") }
        #expect(throws: LookStoreError.newerVersion(path: path, version: 3)) { try store.duplicate(id) }
        #expect(try Data(contentsOf: url) == Data(json.utf8)); try store.delete(id); #expect(store.all().isEmpty) }
}
