import CoreMedia
import Testing
@testable import OpenCam

@Suite struct WriterClipStateTests {
    let frame = CMTime(value: 1, timescale: 30)
    let start = CMTime(value: 1000, timescale: 30)

    func pts(_ index: Int) -> CMTime { CMTimeAdd(start, CMTime(value: CMTimeValue(index), timescale: 30)) }
    /// Arrival of frame `index` when the camera delivers on time, plus `lag` seconds.
    func arrival(_ index: Int, lag: Double = 0) -> Duration { .seconds(Double(index) / 30 + lag) }

    func state(_ policy: DropPolicy = .keepRecording, minFreeBytes: Int64 = 100) -> WriterClipState {
        WriterClipState(policy: policy, frameDuration: frame, minFreeBytes: minFreeBytes)
    }

    /// Delivers and writes frames `0..<count`.
    func write(_ clip: inout WriterClipState, frames count: Int) {
        for index in 0..<count {
            _ = clip.video(pts: pts(index), duration: frame, arrival: arrival(index), isWriterReady: true)
            _ = clip.videoWritten(true, pts: pts(index), duration: frame)
        }
    }

    @Test func theFirstFrameStartsTheSessionAtItsOwnTime() {
        var clip = state()
        let r1 = clip.video(pts: pts(0), duration: frame, arrival: arrival(0), isWriterReady: true)
        #expect(r1 == .startAndWrite(at: pts(0)))
        let r2 = clip.video(pts: pts(1), duration: frame, arrival: arrival(1), isWriterReady: true)
        #expect(r2 == .write)
        #expect(clip.isInFlight)
        #expect(clip.facts.total == 0)
    }

    @Test func soundBeforeTheFirstVideoFrameIsNotWritten() {
        var clip = state()
        let r3 = clip.audio(pts: pts(0), isWriterReady: true)
        #expect(!r3)
        #expect(clip.facts.total == 0)
        #expect(clip.facts.audioBuffersNotWritten == 0)
        _ = clip.video(pts: pts(5), duration: frame, arrival: arrival(0), isWriterReady: true)
        let r4 = clip.audio(pts: pts(2), isWriterReady: true)
        #expect(!r4)   // earlier than the session start
        let r5 = clip.audio(pts: pts(5), isWriterReady: true)
        #expect(r5)
        let r6 = clip.audio(pts: pts(6), isWriterReady: false)
        #expect(!r6)
        #expect(clip.facts.audioBuffersNotWritten == 1)
        #expect(clip.facts.total == 0)
    }

    @Test func aFrameTheWriterIsNotReadyForIsADrop() {
        var clip = state()
        write(&clip, frames: 2)
        let r7 = clip.video(pts: pts(2), duration: frame, arrival: arrival(2), isWriterReady: false)
        #expect(r7 == .skip)
        #expect(clip.facts.total == 1)
        #expect(clip.facts.byReason[DropReason.writerNotReady.rawValue] == 1)
        #expect(clip.isInFlight)
    }

    @Test func aFirstFrameTheWriterIsNotReadyForDoesNotStartTheSession() {
        var clip = state()
        let r8 = clip.video(pts: pts(0), duration: frame, arrival: arrival(0), isWriterReady: false)
        #expect(r8 == .skip)
        let r9 = clip.video(pts: pts(1), duration: frame, arrival: arrival(1), isWriterReady: true)
        #expect(r9 == .startAndWrite(at: pts(1)))
        #expect(clip.facts.total == 1)
    }

    @Test func aFrameMoreThanOneFrameBehindIsDropped() {
        var clip = state()
        write(&clip, frames: 1)
        // Exactly one frame behind real time still writes.
        let r10 = clip.video(pts: pts(1), duration: frame, arrival: arrival(1, lag: 1.0 / 30), isWriterReady: true)
        #expect(r10 == .write)
        // One frame and a millisecond skips.
        let r11 = clip.video(pts: pts(2), duration: frame, arrival: arrival(2, lag: 1.0 / 30 + 0.001), isWriterReady: true)
        #expect(r11 == .skip)
        #expect(clip.facts.total == 1)
        #expect(clip.facts.byReason[DropReason.behind.rawValue] == 1)
    }

    @Test func outputDropsAreCountedByReason() {
        #expect(DropReason(attachment: kCMSampleBufferDroppedFrameReason_FrameWasLate as String) == .late)
        #expect(DropReason(attachment: kCMSampleBufferDroppedFrameReason_OutOfBuffers as String) == .outOfBuffers)
        #expect(DropReason(attachment: kCMSampleBufferDroppedFrameReason_Discontinuity as String) == .discontinuity)
        #expect(DropReason(attachment: nil) == .other)
        #expect(DropReason(attachment: "something new") == .other)
        var clip = state()
        write(&clip, frames: 2)
        let r12 = clip.outputDropped(.late)
        #expect(r12 == .none)
        let r13 = clip.outputDropped(.late)
        #expect(r13 == .none)
        let r14 = clip.outputDropped(.outOfBuffers)
        #expect(r14 == .none)
        let r15 = clip.renderFailed()
        #expect(r15 == .none)
        #expect(clip.facts.total == 4)
        #expect(clip.facts.byReason == ["late": 2, "outOfBuffers": 1, "renderFailed": 1])
    }

    @Test func keepRecordingNeverStopsForDrops() {
        var clip = state(.keepRecording)
        write(&clip, frames: 2)
        for _ in 0..<20 { let finish = clip.outputDropped(.late); #expect(finish == .none) }
        let r16 = clip.video(pts: pts(2), duration: frame, arrival: arrival(2), isWriterReady: false)
        #expect(r16 == .skip)
        let r17 = clip.takePendingFinish()
        #expect(r17 == .none)
        #expect(clip.isInFlight)
        #expect(!clip.facts.stoppedRecording)
        let r18 = clip.video(pts: pts(3), duration: frame, arrival: arrival(3), isWriterReady: true)
        #expect(r18 == .write)
    }

    @Test func stopRecordingStopsOnceAtTheFirstDropAfterAFrameIsWritten() {
        var clip = state(.stopRecording)
        let r19 = clip.outputDropped(.discontinuity)
        #expect(r19 == .none)   // before anything was written: counts only
        #expect(clip.isInFlight)
        write(&clip, frames: 3)
        let r20 = clip.outputDropped(.late)
        #expect(r20 == .finish(endTime: CMTimeAdd(pts(2), frame)))
        #expect(clip.end == .droppedFrames)
        #expect(clip.facts.stoppedRecording)
        let r21 = clip.outputDropped(.late)
        #expect(r21 == .none)
        let r22 = clip.video(pts: pts(3), duration: frame, arrival: arrival(3), isWriterReady: true)
        #expect(r22 == .ignore)
        #expect(clip.facts.total == 2)
        #expect(!clip.isInFlight)
    }

    @Test func aDropFoundWhileDecidingAFrameStopsTheClipOnce() {
        var clip = state(.stopRecording)
        write(&clip, frames: 2)
        let r23 = clip.video(pts: pts(2), duration: frame, arrival: arrival(2), isWriterReady: false)
        #expect(r23 == .skip)
        #expect(clip.end == .droppedFrames)
        let r24 = clip.takePendingFinish()
        #expect(r24 == .finish(endTime: CMTimeAdd(pts(1), frame)))
        let r25 = clip.takePendingFinish()
        #expect(r25 == .none)
    }

    @Test func everyEndAfterAFirstFrameFinishesAtTheLastFrameAndNeverCancels() {
        let ends: [WriterEnd] = [.user, .droppedFrames, .storageFull, .interrupted, .cameraStopped, .writerFailed, .timedOut]
        for reason in ends {
            var clip = state()
            write(&clip, frames: 4)
            let r26 = clip.end(reason)
            #expect(r26 == .finish(endTime: CMTimeAdd(pts(3), frame)), "\(reason)")
            #expect(clip.end == reason)
            #expect(!clip.isInFlight)
        }
    }

    @Test func anEndBeforeAnyFrameCancels() {
        var clip = state()
        let r27 = clip.end(.user)
        #expect(r27 == .cancel)
        var started = state()
        _ = started.video(pts: pts(0), duration: frame, arrival: arrival(0), isWriterReady: true)   // started, never written
        let r28 = started.end(.interrupted)
        #expect(r28 == .cancel)
    }

    @Test func aSecondEndDoesNothing() {
        var clip = state()
        write(&clip, frames: 2)
        let r29 = clip.end(.storageFull)
        #expect(r29 != .none)
        let r30 = clip.end(.user)
        #expect(r30 == .none)
        let r31 = clip.end(.interrupted)
        #expect(r31 == .none)
        #expect(clip.end == .storageFull)
        let r32 = clip.storage(freeBytes: 0)
        #expect(r32 == .none)
        var empty = state()
        let r33 = empty.end(.user)
        #expect(r33 == .cancel)
        let r34 = empty.end(.cameraStopped)
        #expect(r34 == .none)
    }

    @Test func aFailedWriteEndsTheClipAsWriterFailed() {
        var clip = state()
        write(&clip, frames: 2)
        _ = clip.video(pts: pts(2), duration: frame, arrival: arrival(2), isWriterReady: true)
        let r35 = clip.videoWritten(false, pts: pts(2), duration: frame)
        #expect(r35 == .finish(endTime: CMTimeAdd(pts(1), frame)))
        #expect(clip.end == .writerFailed)
        var first = state()
        _ = first.video(pts: pts(0), duration: frame, arrival: arrival(0), isWriterReady: true)
        let r36 = first.videoWritten(false, pts: pts(0), duration: frame)
        #expect(r36 == .cancel)
    }

    @Test func lowStorageEndsTheClip() {
        var clip = state(minFreeBytes: 100)
        write(&clip, frames: 2)
        let r37 = clip.storage(freeBytes: 101)
        #expect(r37 == .none)
        #expect(clip.isInFlight)
        let r38 = clip.storage(freeBytes: 100)
        #expect(r38 == .finish(endTime: CMTimeAdd(pts(1), frame)))
        #expect(clip.end == .storageFull)
    }

    @Test func dropReportsComeAtOnceThenAtMostFourASecond() {
        var clip = state()
        let r39 = clip.dropCountToReport(arrival: .seconds(0))
        #expect(r39 == nil)   // nothing dropped yet
        _ = clip.outputDropped(.late)
        let r40 = clip.dropCountToReport(arrival: .milliseconds(1000))
        #expect(r40 == 1)
        for _ in 0..<10 { _ = clip.outputDropped(.late) }
        let r41 = clip.dropCountToReport(arrival: .milliseconds(1100))
        #expect(r41 == nil)
        let r42 = clip.dropCountToReport(arrival: .milliseconds(1249))
        #expect(r42 == nil)
        let r43 = clip.dropCountToReport(arrival: .milliseconds(1250))
        #expect(r43 == 11)
        let r44 = clip.dropCountToReport(arrival: .milliseconds(1600))
        #expect(r44 == nil)   // nothing new
    }

    /// Delivers frame `index` arriving `delay` seconds after its on-time arrival; writes it when the state says so.
    /// Returns whether it was written.
    func deliver(_ clip: inout WriterClipState, _ index: Int, delay: Double = 0) -> Bool {
        let step = clip.video(pts: pts(index), duration: frame, arrival: arrival(index, lag: delay), isWriterReady: true)
        switch step {
        case .startAndWrite, .write:
            _ = clip.videoWritten(true, pts: pts(index), duration: frame)
            return true
        case .skip, .ignore:
            return false
        }
    }

    @Test func aLastingRiseInDeliveryDelayStopsDroppingWithinAboutASecond() {
        var clip = state(.keepRecording)
        var written = [Bool]()
        for index in 0..<200 {
            // From frame 60 every frame arrives 1.5 frame times later than before, forever.
            written.append(deliver(&clip, index, delay: index >= 60 ? 1.5 / 30 : 0))
        }
        let skipped = written.indices.filter { !written[$0] }
        #expect(!skipped.isEmpty)
        #expect(skipped.allSatisfy { $0 >= 60 })
        #expect(skipped.count <= 35)
        #expect(written[100...].allSatisfy { $0 })
        #expect(clip.facts.total == skipped.count)
        #expect(clip.facts.byReason[DropReason.behind.rawValue] == skipped.count)
        #expect(clip.end == nil)
    }

    @Test func aShortHiccupDropsOnlyUntilCaughtUp() {
        var clip = state(.keepRecording)
        for index in 0..<10 { #expect(deliver(&clip, index)) }
        // Frame 10 is delivered 3 frame times late; 11 to 13 follow back to back, at the same instant.
        let late = 3.0 / 30
        func hiccup(from first: Int) -> [Bool] {
            (0..<4).map { offset in
                let index = first + offset
                // All four arrive when frame `first` would have, 3 frame times late.
                return deliver(&clip, index, delay: late - Double(offset) / 30)
            }
        }
        #expect(hiccup(from: 10) == [false, false, true, true])
        for index in 14..<40 { #expect(deliver(&clip, index)) }
        // The baseline did not move: the same hiccup later behaves the same.
        #expect(hiccup(from: 40) == [false, false, true, true])
        for index in 44..<60 { #expect(deliver(&clip, index)) }
        #expect(clip.facts.total == 4)
        #expect(clip.end == nil)
    }

    @Test func factsCountDeliveredAndWritten() {
        var clip = state()
        write(&clip, frames: 3)
        _ = clip.video(pts: pts(3), duration: frame, arrival: arrival(3), isWriterReady: false)
        #expect(clip.facts.framesDelivered == 4)
        #expect(clip.facts.framesWritten == 3)
        #expect(clip.facts.total == 1)
    }
}
