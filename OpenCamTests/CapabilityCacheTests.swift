import Foundation
import Testing
@testable import OpenCam

@Suite struct CapabilityCacheTests {
    func tempDirectory() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }
    @Test func olderOSBuildTriggersRescan() throws {
        let cache = CapabilityCache(directory: tempDirectory())
        var caps = try Fixture.load(); caps.osBuild = "24B91"; caps.modelIdentifier = "iPhone19,4"
        try cache.save(caps)
        #expect(cache.load(osBuild: "24B114", modelIdentifier: "iPhone19,4") == nil)
        #expect(cache.load(osBuild: "24B91", modelIdentifier: "iPhone19,5") == nil)
        #expect(cache.load(osBuild: "24B91", modelIdentifier: "iPhone19,4") == caps)
    }
    @Test func corruptFileIsAMiss() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appending(path: "capabilities.json"))
        #expect(CapabilityCache(directory: dir).load(osBuild: "B", modelIdentifier: "M") == nil)
    }
}
