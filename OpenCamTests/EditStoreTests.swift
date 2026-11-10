import Foundation
import Testing
@testable import OpenCam

@Suite struct EditStoreTests {
    @Test func newerEditFileWithUnknownKeysLoads() throws {
        let dir = try TestFiles.directory()
        let json = #"{"version": 3, "lookName": "Warm fade", "adjustments": {"exposure": 1, "toneCurve": [[0, 0], [1, 1]]}, "masks": [{"kind": "sky"}], "crop": {"angle": 2}}"#
        try Data(json.utf8).write(to: dir.appending(path: "OC_0001.edit.json"))
        let edit = try EditStore(directory: dir).load(stem: "OC_0001")
        #expect(edit.adjustments == Adjustments().setting(.exposure, to: 1)); #expect(edit.lookName == "Warm fade"); #expect(edit.version == 3)
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
}
