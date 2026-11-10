import Foundation
import Testing
@testable import OpenCam

@Suite struct FailedCombinationsTests {
    let bad = VideoOption(lensID: "wide", codec: VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .appleLog2)
    let good = VideoOption(lensID: "wide", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
    @Test func captionAppearsAndDisappears() {
        let failed = FailedCombinations(osBuild: "B", failedByLens: [:]).replacing(lensID: "wide", with: [bad])
        #expect(failed.caption(for: bad) == "This combination did not record in the last format sweep.")
        #expect(failed.caption(for: good) == nil); #expect(failed.caption(for: nil) == nil)
        #expect(failed.replacing(lensID: "wide", with: []).caption(for: bad) == nil)
    }
    @Test func anotherOSBuildClearsTheSet() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FailedCombinations(osBuild: "24B91", failedByLens: ["wide": [bad]]).save(directory: dir)
        #expect(FailedCombinations.load(directory: dir, osBuild: "24B91").caption(for: bad) != nil)
        #expect(FailedCombinations.load(directory: dir, osBuild: "24B114").caption(for: bad) == nil)
    }

    // Beyond the brief: replacing one lens leaves the others, and a missing file loads empty.
    @Test func replacingOneLensKeepsTheOthers() {
        let front = VideoOption(lensID: "front", codec: good.codec, resolution: good.resolution, frameRate: 30, colour: .rec709)
        let failed = FailedCombinations(osBuild: "B", failedByLens: ["front": [front]]).replacing(lensID: "wide", with: [bad])
        #expect(failed.caption(for: front) != nil); #expect(failed.caption(for: bad) != nil)
        #expect(failed.replacing(lensID: "wide", with: []).caption(for: front) != nil)
    }
    @Test func updatingKeepsEntriesThisSweepDidNotAnswer() {
        let slow = VideoOption(lensID: "wide", codec: good.codec, resolution: .named(width: 1920, height: 1080), frameRate: 30, colour: .rec709)
        let before = FailedCombinations(osBuild: "B", failedByLens: ["wide": [bad, slow]])
        // `bad` now passes, `good` now fails, `slow` timed out or was never reached: it keeps its entry.
        let after = before.updating(lensID: "wide", passed: [bad], failed: [good])
        #expect(after.failedByLens["wide"] == [slow, good])
        #expect(after.updating(lensID: "wide", passed: [], failed: [good]).failedByLens["wide"] == [slow, good])
        #expect(after.updating(lensID: "wide", passed: [slow, good], failed: []).failedByLens["wide"] == nil)
    }

    @Test func missingFileLoadsEmpty() {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let loaded = FailedCombinations.load(directory: dir, osBuild: "B")
        #expect(loaded == FailedCombinations(osBuild: "B", failedByLens: [:]))
    }
}
