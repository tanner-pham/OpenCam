import AVFoundation
import Testing
@testable import OpenCam

@Suite struct RecordingOutcomeTests {
    func error(_ code: AVError.Code, finished: Bool) -> NSError {
        NSError(domain: AVFoundationErrorDomain, code: code.rawValue, userInfo: [AVErrorRecordingSuccessfullyFinishedKey: finished])
    }
    @Test func diskFullStopsCleanlyAndKeepsPlayableFile() {
        let outcome = RecordingOutcome(error: error(.diskFull, finished: true))
        #expect(outcome == .stopped(.storageFull, isPlayable: true)); #expect(outcome.notice == "Recording stopped. Storage is full. Clip saved.")
    }
    @Test func interruptionFinalizesFile() {
        #expect(RecordingOutcome(error: error(.sessionWasInterrupted, finished: true)) == .stopped(.interrupted, isPlayable: true))
        #expect(RecordingOutcome(error: error(.sessionWasInterrupted, finished: false)).notice == "Recording failed. The clip could not be saved.")
        #expect(RecordingOutcome(error: nil) == .completed)
    }
    @Test func droppedFramesNoticeCountsCorrectly() {
        #expect(RecordingOutcome.droppedFramesNotice(clipName: "OC_0002", droppedFrames: 0) == nil)
        #expect(RecordingOutcome.droppedFramesNotice(clipName: "OC_0002", droppedFrames: 1) == "OC_0002 dropped 1 frame.")
        #expect(RecordingOutcome.droppedFramesNotice(clipName: "OC_0002", droppedFrames: 5) == "OC_0002 dropped 5 frames.")
    }
}
