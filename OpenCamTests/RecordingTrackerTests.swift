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
        #expect(tracker.isAwaitingResult)
        tracker.reported()
        #expect(!tracker.isAwaitingResult)
    }

    @Test func aFileThatWasNeverStartedIsNotMatched() {
        var tracker = RecordingTracker()
        tracker.begin(clip(second))
        let unknown = tracker.finish(url: first)
        #expect(unknown == nil); #expect(tracker.pending?.url == second)
    }
}
