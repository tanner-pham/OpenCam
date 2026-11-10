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
    @Test func cacheWithSkippedLensesIsStillAHitUnderTheSubsetRule() throws {
        let cache = CapabilityCache(directory: tempDirectory())
        var caps = try Fixture.load(); caps.lenses.removeAll { $0.id == "outer" }; caps.skippedLensIDs = ["outer"]
        try cache.save(caps)
        let loaded = try #require(cache.load(osBuild: caps.osBuild, modelIdentifier: caps.modelIdentifier))
        #expect(loaded.skippedLensIDs == ["outer"])
        let adopted = try #require(loaded.adopting(discovered: try Fixture.load().lenses))
        #expect(adopted.lenses.map(\.id) == caps.lenses.map(\.id)); #expect(adopted.skippedLensIDs == ["outer"])
        #expect(loaded.adopting(discovered: caps.lenses.filter { $0.id != "wide" }) == nil)
    }
    @Test func corruptFileIsAMiss() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appending(path: "capabilities.json"))
        #expect(CapabilityCache(directory: dir).load(osBuild: "B", modelIdentifier: "M") == nil)
    }
}
