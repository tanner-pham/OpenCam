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
    @Test func aClipWithNoReportedEndIsNeverCalledLost() {
        #expect(RecordingOutcome.stopped(.noResult, isPlayable: false).notice == "Recording stopped. The clip may be incomplete.")
        #expect(!RecordingOutcome.stopped(.noResult, isPlayable: false).isPlayable)
    }
    @Test func aWriterClipEndsAsTheRowsSay() {
        func outcome(_ end: WriterEnd, hasFrames: Bool = true, isReadable: Bool = true) -> RecordingOutcome {
            RecordingOutcome(writerEnd: end, hasFrames: hasFrames, isReadable: isReadable)
        }
        #expect(outcome(.user) == .completed)
        #expect(outcome(.droppedFrames) == .stopped(.droppedFrames, isPlayable: true))
        #expect(outcome(.storageFull) == .stopped(.storageFull, isPlayable: true))
        #expect(outcome(.interrupted) == .stopped(.interrupted, isPlayable: true))
        #expect(outcome(.cameraStopped) == .stopped(.writerFailed, isPlayable: true))
        #expect(outcome(.writerFailed) == .stopped(.writerFailed, isPlayable: true))
        #expect(outcome(.timedOut) == .stopped(.noResult, isPlayable: false))
        #expect(outcome(.timedOut, isReadable: false) == .stopped(.noResult, isPlayable: false))
    }
    @Test func aWriterClipWithNoFramesFailsAndAnUnreadableFileIsNotPlayable() {
        for end in [WriterEnd.user, .droppedFrames, .storageFull, .interrupted, .cameraStopped, .writerFailed, .timedOut] {
            let none = RecordingOutcome(writerEnd: end, hasFrames: false, isReadable: false)
            guard case .failed = none else { Issue.record("\(end) with no frames gave \(none)"); continue }
            #expect(!none.isPlayable); #expect(none.notice == RecordingOutcome.failedNotice)
            let unreadable = RecordingOutcome(writerEnd: end, hasFrames: true, isReadable: false)
            #expect(!unreadable.isPlayable); #expect(unreadable.notice != nil)
        }
        #expect(RecordingOutcome(writerEnd: .storageFull, hasFrames: true, isReadable: false) == .stopped(.storageFull, isPlayable: false))
        #expect(RecordingOutcome(writerEnd: .storageFull, hasFrames: true, isReadable: false).notice == RecordingOutcome.failedNotice)
    }
    @Test func theWriterNoticesSayWhatHappenedAndHaveNoEmDash() {
        #expect(RecordingOutcome.droppedFramesStopNotice == "Recording stopped. A frame was dropped. Clip saved.")
        #expect(RecordingOutcome.stopped(.droppedFrames, isPlayable: true).notice == RecordingOutcome.droppedFramesStopNotice)
        #expect(RecordingOutcome.stopped(.droppedFrames, isPlayable: false).notice == RecordingOutcome.failedNotice)
        #expect(RecordingOutcome.stopped(.writerFailed, isPlayable: true).notice == RecordingOutcome.incompleteNotice)
        #expect(RecordingOutcome.stopped(.writerFailed, isPlayable: false).notice == RecordingOutcome.failedNotice)
        #expect(RecordingOutcome.stopped(.droppedFrames, isPlayable: true).isPlayable)
        for text in [RecordingOutcome.droppedFramesStopNotice, RecordingOutcome.incompleteNotice] { #expect(!text.contains("\u{2014}")) }
    }
    @Test func droppedFramesNoticeCountsCorrectly() {
        #expect(RecordingOutcome.droppedFramesNotice(clipName: "OC_0002", droppedFrames: 0) == nil)
        #expect(RecordingOutcome.droppedFramesNotice(clipName: "OC_0002", droppedFrames: 1) == "OC_0002 dropped 1 frame.")
        #expect(RecordingOutcome.droppedFramesNotice(clipName: "OC_0002", droppedFrames: 5) == "OC_0002 dropped 5 frames.")
    }
}
