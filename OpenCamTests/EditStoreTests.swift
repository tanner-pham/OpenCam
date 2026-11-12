import Foundation
import Testing
@testable import OpenCam

@Suite struct EditStoreTests {
    @Test func newerEditFileWithUnknownKeysLoads() throws {
        let dir = try TestFiles.directory()
        let json = #"{"version": 4, "lookName": "Warm fade", "adjustments": {"exposure": 1, "toneCurve": [[0, 0], [1, 1]]}, "masks": [{"kind": "sky"}], "crop": {"angle": 2}}"#
        try Data(json.utf8).write(to: dir.appending(path: "OC_0001.edit.json"))
        let edit = try EditStore(directory: dir).load(stem: "OC_0001")
        #expect(edit.adjustments == Adjustments().setting(.exposure, to: 1)); #expect(edit.lookName == "Warm fade"); #expect(edit.version == 4); #expect(edit.masks == [])
    }
    @Test func roundTripAndMissingFile() throws {
        let store = EditStore(directory: try TestFiles.directory())
        #expect(try store.load(stem: "OC_0002") == PhotoEdit())
        let edit = PhotoEdit(adjustments: Adjustments().setting(.shadows, to: 30), lookName: "Warm fade")
        try store.save(edit, stem: "OC_0002")
        #expect(try store.load(stem: "OC_0002") == edit); #expect(EditStore.fileName(forStem: "OC_0002") == "OC_0002.edit.json")
    }
    @Test func identityEditWithoutLookRemovesTheFile() throws {
        let store = EditStore(directory: try TestFiles.directory())
        let path = store.url(forStem: "OC_0003").path(percentEncoded: false)
        try store.save(PhotoEdit(adjustments: Adjustments().setting(.tint, to: 5)), stem: "OC_0003"); #expect(FileManager.default.fileExists(atPath: path))
        try store.save(PhotoEdit(), stem: "OC_0003"); #expect(!FileManager.default.fileExists(atPath: path))
        try store.save(PhotoEdit(lookName: "Plain"), stem: "OC_0003"); #expect(FileManager.default.fileExists(atPath: path))
        try store.remove(stem: "OC_0003"); try store.remove(stem: "OC_0003")
        #expect(!FileManager.default.fileExists(atPath: path))
    }
    @Test func unreadableEditThrows() throws {
        let dir = try TestFiles.directory()
        try Data("{".utf8).write(to: dir.appending(path: "OC_0004.edit.json"))
        #expect(throws: EditStoreError.self) { try EditStore(directory: dir).load(stem: "OC_0004") }
    }
    @Test func newerVersionFileIsReadOnly() throws {
        let dir = try TestFiles.directory()
        let url = dir.appending(path: "OC_0005.edit.json")
        let json = #"{"version": 4, "lookName": "Warm fade", "adjustments": {"exposure": 1}, "masks": [{"kind": "sky"}]}"#
        try Data(json.utf8).write(to: url)
        let store = EditStore(directory: dir)
        var edit = try store.load(stem: "OC_0005")
        edit.adjustments.exposure = 2
        #expect(throws: EditStoreError.newerVersion(path: url.path(percentEncoded: false), version: 4)) { try store.save(edit, stem: "OC_0005") }
        #expect(throws: EditStoreError.self) { try store.save(PhotoEdit(), stem: "OC_0005") }
        #expect(throws: EditStoreError.self) { try store.remove(stem: "OC_0005") }
        #expect(try Data(contentsOf: url) == Data(json.utf8))
    }
    @Test func editFilesDoNotDisturbCaptureNumbering() throws {
        let dir = try TestFiles.directory()
        try Data().write(to: dir.appending(path: "OC_0001.HEIC"))
        try Data("{}".utf8).write(to: dir.appending(path: "OC_0001.edit.json"))
        #expect(try CaptureStore(directory: dir).reserveSequence() == 2)
        #expect(CaptureStore.latestCaptureName(["OC_0001.HEIC", "OC_0009.edit.json"]) == "OC_0001.HEIC")
        // nextSequence reads the number before the first dot, so an edit file with a higher number does raise it. Harmless: numbers only skip ahead.
        #expect(CaptureStore.nextSequence(existingNames: ["OC_0001.HEIC", "OC_0009.edit.json"]) == 10)
    }

    @Test func resavingAnOldEditStampsTheCurrentVersion() throws {   // Review Focus 1
        let dir = try TestFiles.directory(), store = EditStore(directory: dir); #expect(PhotoEdit.currentVersion == 3)
        for (stem, json) in [("OC_0006", #"{"version": 1, "adjustments": {"exposure": 1}}"#), ("OC_0007", #"{"adjustments": {"exposure": 1}}"#)] {
            let url = dir.appending(path: "\(stem).edit.json"); try Data(json.utf8).write(to: url); var edit = try store.load(stem: stem)
            #expect(edit.version == 1); #expect(edit.adjustments == Adjustments().setting(.exposure, to: 1))
            edit.adjustments.exposure = 2; try store.save(edit, stem: stem); #expect(try JSONDecoder().decode(EditFileVersion.self, from: Data(contentsOf: url)).version == PhotoEdit.currentVersion); #expect(try store.load(stem: stem).version == PhotoEdit.currentVersion) } }
}
