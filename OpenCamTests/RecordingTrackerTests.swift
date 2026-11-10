import Foundation
import Testing
@testable import OpenCam

@Suite struct RecordingTrackerTests {
    let option = VideoOption(lensID: "wide", codec: VideoCodec(family: .hevc, quality: "High", codecType: "hvc1", bitrateTier: .high),
                             resolution: .named(width: 3840, height: 2160), frameRate: 30, colour: .rec709)
    let first = URL(filePath: "/tmp/OC_0001.MOV")
    let second = URL(filePath: "/tmp/OC_0002.MOV")

    func clip(_ url: URL) -> PendingRecording {
        PendingRecording(url: url, option: option, recordedAt: Date(), onFinish: {})
    }

    @Test func aLateResultForAnEarlierClipLeavesTheNewClipPending() throws {
        var tracker = RecordingTracker()
        tracker.begin(clip(first))
        // The first clip's end was never reported (a restart), and a new clip starts.
        tracker.begin(clip(second))
        let lateFinish = tracker.finish(url: first)
        let late = try #require(lateFinish)
        #expect(late.recording.url == first); #expect(!late.isCurrent)
        #expect(tracker.pending?.url == second)
        tracker.reported()
        let currentFinish = tracker.finish(url: second)
        let current = try #require(currentFinish)
        #expect(current.recording.url == second); #expect(current.isCurrent); #expect(tracker.pending == nil)
        let finishing = tracker.requestStop()
        #expect(finishing == .awaitingResult)
        tracker.reported()
        let done = tracker.requestStop()
        #expect(done == .nothingInFlight)
    }

    @Test func theSameFileReportedThroughPrivateVarIsTheSameClip() throws {
        let container = "/var/mobile/Containers/Data/Application/0A1B/Documents/Captures"
        let given = URL(filePath: "\(container)/OC_0002.MOV")
        let reported = URL(filePath: "/private\(container)/OC_0002.MOV")
        var tracker = RecordingTracker()
        tracker.begin(clip(URL(filePath: "\(container)/OC_0001.MOV")))
        tracker.begin(clip(given))
        let start = tracker.didStart(url: reported)
        #expect(!start)
        let stop = tracker.requestStop()
        #expect(stop == .stopNow)
        // A different file name, in either spelling, is still the earlier clip.
        let earlierFinish = tracker.finish(url: URL(filePath: "/private\(container)/OC_0001.MOV"))
        let earlier = try #require(earlierFinish)
        #expect(!earlier.isCurrent); #expect(tracker.pending?.url == given)
        let currentFinish = tracker.finish(url: reported)
        let current = try #require(currentFinish)
        #expect(current.isCurrent); #expect(current.recording.url == given); #expect(tracker.pending == nil)
        #expect(CaptureStore.clipKey(for: given) == CaptureStore.clipKey(for: reported))
    }

    @Test func aFileThatWasNeverStartedIsNotMatched() {
        var tracker = RecordingTracker()
        tracker.begin(clip(second))
        let unknown = tracker.finish(url: first)
        #expect(unknown == nil); #expect(tracker.pending?.url == second)
    }

    @Test func aStopBeforeTheOutputStartsIsAppliedWhenItStarts() {
        var tracker = RecordingTracker()
        let idle = tracker.requestStop()
        #expect(idle == .nothingInFlight)
        tracker.begin(clip(first))
        let early = tracker.requestStop()
        #expect(early == .deferred)
        // A start reported for another file changes nothing.
        let otherStart = tracker.didStart(url: second)
        #expect(!otherStart)
        let start = tracker.didStart(url: first)
        #expect(start)
        let later = tracker.requestStop()
        #expect(later == .stopNow)
    }

    @Test func aStopAfterTheStartStopsAtOnceAndAFinishingClipIsStillInFlight() {
        var tracker = RecordingTracker()
        tracker.begin(clip(first))
        let start = tracker.didStart(url: first)
        #expect(!start)
        let running = tracker.requestStop()
        #expect(running == .stopNow)
        let finished = tracker.finish(url: first)
        #expect(finished?.isCurrent == true)
        let finishing = tracker.requestStop()
        #expect(finishing == .awaitingResult)
        tracker.reported()
        let done = tracker.requestStop()
        #expect(done == .nothingInFlight)
    }

    @Test func aDeferredStopDoesNotCarryOverToTheNextClip() {
        var tracker = RecordingTracker()
        tracker.begin(clip(first))
        _ = tracker.requestStop()
        tracker.begin(clip(second))
        let start = tracker.didStart(url: second)
        #expect(!start)
    }
}
