import Foundation
import Testing
@testable import OpenCam

@Suite struct FormatSweepTests {
    let ask = VideoOption(lensID: "wide", codec: VideoCodec(family: .proRes, quality: "422 HQ", codecType: "apch", bitrateTier: nil), resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .appleLog2)
    func facts(codec: String = "apch", w: Int = 3840, h: Int = 2160, colour: ColourMode? = .appleLog2, duration: Double = 3) -> ClipFacts {
        ClipFacts(codecFourCC: codec, width: w, height: h, nominalFrameRate: 29.97, durationSeconds: duration, frameCount: 90, droppedFrames: 0, colour: colour, megabitsPerSecond: 880, hasAudio: true)
    }
    @Test func matchingAndRotatedClipsPass() {
        #expect(SweepRow.evaluate(requested: ask, facts: facts(), error: nil).status == .pass)
        #expect(SweepRow.evaluate(requested: ask, facts: facts(w: 2160, h: 3840), error: nil).status == .pass)
    }
    @Test func mismatchesFailWithAReason() {
        #expect(SweepRow.evaluate(requested: ask, facts: facts(codec: "hvc1"), error: nil).error == "Asked for apch, file has hvc1.")
        #expect(SweepRow.evaluate(requested: ask, facts: facts(colour: .rec709), error: nil).error == "Asked for Apple Log 2, file has Rec. 709.")
        #expect(SweepRow.evaluate(requested: ask, facts: facts(duration: 1.2), error: nil).error == "Clip is 1.2 s, expected 3 s.")
        let errored = SweepRow.evaluate(requested: ask, facts: nil, error: "[MovieRecorder:start] Cannot record — {codec: apch}")
        #expect(errored.status == .fail); #expect(errored.error == "Recording failed.")
        #expect(errored.detail == "[MovieRecorder:start] Cannot record — {codec: apch}")
    }
    @Test func anAnswerFollowsTheTimeoutFlagNotTheText() throws {
        let timedOut = SweepRow.timedOut(requested: ask, detail: "[FormatSweep:run] No answer before the deadline — {step: finish, codec: apch}")
        #expect(timedOut.isTimedOut); #expect(!timedOut.hasAnswer)
        // Text alone never decides it.
        let sameText = SweepRow(requested: ask, actual: nil, status: .fail, error: SweepRow.didNotFinish, detail: nil)
        #expect(!sameText.isTimedOut); #expect(sameText.hasAnswer)
        #expect(!timedOut.recordedWithoutCamera().hasAnswer); #expect(!sameText.recordedWithoutCamera().hasAnswer)
        // Round trip, and a report written before either flag existed.
        let decoder = JSONDecoder()
        #expect(try decoder.decode(SweepRow.self, from: JSONEncoder().encode(timedOut)) == timedOut)
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        let olderJSON = try #require(String(data: sorted.encode(SweepRow.evaluate(requested: ask, facts: facts(), error: nil)), encoding: .utf8))
            .replacingOccurrences(of: "\"isTimedOut\":false,", with: "").replacingOccurrences(of: ",\"wasCameraUsable\":true", with: "")
        #expect(!olderJSON.contains("isTimedOut")); #expect(!olderJSON.contains("wasCameraUsable"))
        let decoded = try decoder.decode(SweepRow.self, from: Data(olderJSON.utf8))
        #expect(!decoded.isTimedOut); #expect(decoded.wasCameraUsable); #expect(decoded.hasAnswer)
    }

    @Test func reportFileName() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-09T14:30:05Z"))
        #expect(SweepReport.fileName(for: date, timeZone: try #require(TimeZone(identifier: "UTC"))) == "sweep-2026-11-09-143005.json")
    }

    // Beyond the brief: the remaining failure texts, their order, and what does not fail.
    @Test func dimensionsAndFrameRateFailWithAReason() {
        #expect(SweepRow.evaluate(requested: ask, facts: facts(w: 1920, h: 1080), error: nil).error == "Asked for 3840 x 2160, file has 1920 x 1080.")
        let slow = ClipFacts(codecFourCC: "apch", width: 3840, height: 2160, nominalFrameRate: 29.97, durationSeconds: 3, frameCount: 90, droppedFrames: 0, colour: .appleLog2, megabitsPerSecond: 880, hasAudio: true)
        let sixty = VideoOption(lensID: "wide", codec: ask.codec, resolution: ask.resolution, frameRate: 60, colour: .appleLog2)
        #expect(SweepRow.evaluate(requested: sixty, facts: slow, error: nil).error == "Asked for 60 fps, file has 30.0 fps.")
    }
    @Test func firstMismatchWinsAndUnknownsDoNotFail() {
        #expect(SweepRow.evaluate(requested: ask, facts: facts(codec: "hvc1", w: 1920, h: 1080), error: nil).error == "Asked for apch, file has hvc1.")
        let unknownColour = SweepRow.evaluate(requested: ask, facts: facts(colour: nil), error: nil)
        #expect(unknownColour.status == .pass); #expect(unknownColour.error == nil); #expect(unknownColour.detail == nil)
        let dropped = ClipFacts(codecFourCC: "apch", width: 3840, height: 2160, nominalFrameRate: 30, durationSeconds: 3, frameCount: 85, droppedFrames: 5, colour: .appleLog2, megabitsPerSecond: 880, hasAudio: true)
        #expect(SweepRow.evaluate(requested: ask, facts: dropped, error: nil).status == .pass)
        let unread = SweepRow.evaluate(requested: ask, facts: nil, error: nil)
        #expect(unread.status == .fail); #expect(unread.error == "Recording failed.")
    }
    @Test func summaryCountsPassesAndFailures() {
        let pass = SweepRow.evaluate(requested: ask, facts: facts(), error: nil)
        let fail = SweepRow.evaluate(requested: ask, facts: nil, error: "x")
        func report(_ rows: [SweepRow]) -> SweepReport {
            SweepReport(startedAt: Date(), finishedAt: Date(), lensID: "wide", osBuild: "B", modelIdentifier: "M", cancelled: false, endedEarly: false, rows: rows)
        }
        #expect(report([pass, fail]).summary == "1 passed, 1 failed.")
        #expect(report([pass, pass, fail, fail, fail]).summary == "2 passed, 3 failed.")
        #expect(report([]).summary == "0 passed, 0 failed.")
    }
}
