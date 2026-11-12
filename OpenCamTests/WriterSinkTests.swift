import AVFoundation
import Foundation
import Testing
@testable import OpenCam

/// Drives the real `WriterSink` and a real `AVAssetWriter` with synthetic frames. There is no camera in the Simulator, so these
/// are the only tests that write a file; each reads the finished file back.
@Suite struct WriterSinkTests {
    let path = FileManager.default

    @Test func thirtyFramesBecomeAOneSecondClip() async throws {
        let rig = try SinkRig()
        try rig.open()
        try await rig.deliver(frames: 0..<30)
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        let report = try #require(rig.takeReport())
        #expect(report.end == .user)
        #expect(report.hasFrames)
        #expect(report.facts.framesWritten == 30)
        #expect(report.facts.total == 0)
        let facts = try await ClipInspector.inspect(url: rig.url, requestedFrameRate: 30)
        #expect(facts.frameCount == 30)
        #expect(abs(facts.durationSeconds - 1.0) < 0.1)
        #expect(facts.width == SyntheticFrames.width)
        #expect(facts.height == SyntheticFrames.height)
        #expect(RecordingOutcome(writerEnd: report.end, hasFrames: report.hasFrames, isReadable: true) == .completed)
    }

    /// States which codec the other tests wrote with. The Simulator's writer refuses ProRes at start ("Cannot Encode", measured
    /// 2026-11-12), so the rig falls back to H.264 there and every test here ran on H.264; the expectation is recorded as a known
    /// issue in the Simulator and is a plain check on a device.
    @Test func theHostWritesProRes() async throws {
        let rig = try SinkRig()
        let option = try rig.open()
        try await rig.deliver(frames: 0..<3)
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        _ = rig.takeReport()
        let refusals = rig.refusals
        withKnownIssue("The Simulator's writer cannot encode ProRes", isIntermittent: false) {
            #expect(option.codec.codecType == "apco", "ProRes was refused: \(refusals)")
        } when: {
            Self.isSimulator
        }
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    @Test func anInterruptedClipIsStillAPlayableFile() async throws {
        let rig = try SinkRig()
        try rig.open()
        try await rig.deliver(frames: 0..<15)
        #expect(rig.end(.interrupted))
        #expect(await rig.waitForFinishes())
        let report = try #require(rig.takeReport())
        #expect(report.end == .interrupted)
        #expect(report.hasFrames)
        // The finished file opens and has a duration: read it directly, not only through our own inspector.
        let asset = AVURLAsset(url: rig.url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 0.5) < 0.1)
        #expect(try await asset.load(.isPlayable))
        let facts = try await ClipInspector.inspect(url: rig.url, requestedFrameRate: 30)
        #expect(facts.frameCount == 15)
        #expect(facts.durationSeconds > 0)
        #expect(RecordingOutcome(writerEnd: report.end, hasFrames: report.hasFrames, isReadable: true) == .stopped(.interrupted, isPlayable: true))
    }

    @Test func aStopWithNoFrameLeavesNoFileAndReportsNoFrames() async throws {
        let rig = try SinkRig()
        try rig.open()
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        let report = try #require(rig.takeReport())
        #expect(!report.hasFrames)
        #expect(!path.fileExists(atPath: rig.url.path(percentEncoded: false)))
        guard case .failed = RecordingOutcome(writerEnd: report.end, hasFrames: report.hasFrames, isReadable: false) else {
            Issue.record("A clip with no frame should be a failure")
            return
        }
    }

    @Test func stopRecordingPolicyFinishesTheFileAtTheFirstDrop() async throws {
        let rig = try SinkRig()
        try rig.open(policy: .stopRecording)
        try await rig.deliver(frames: 0..<10)
        rig.drop(.late, atFrame: 10)
        #expect(await rig.waitForFinishes())
        // Frames that arrive after the end are ignored.
        try await rig.deliver(frames: 11..<14)
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.finished.value == 1)
        let report = try #require(rig.takeReport())
        #expect(report.end == .droppedFrames)
        #expect(report.facts.stoppedRecording)
        #expect(report.facts.total == 1)
        #expect(report.facts.framesWritten == 10)
        let facts = try await ClipInspector.inspect(url: rig.url, requestedFrameRate: 30)
        #expect(facts.frameCount == 10)
        #expect(RecordingOutcome(writerEnd: report.end, hasFrames: true, isReadable: true).notice == RecordingOutcome.droppedFramesStopNotice)
    }

    @Test func dropsReachOnDrops() async throws {
        let rig = try SinkRig()
        try rig.open(policy: .keepRecording)
        try await rig.deliver(frames: 0..<3)
        rig.drop(.late, atFrame: 3)
        #expect(rig.drops.totals == [1])
        try await rig.deliver(frames: 4..<8)
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        let report = try #require(rig.takeReport())
        #expect(report.end == .user)
        #expect(report.facts.total == 1)
        #expect(report.facts.byReason[DropReason.late.rawValue] == 1)
        #expect(!report.facts.stoppedRecording)
    }

    @Test func twoEndsFinishOnce() async throws {
        let rig = try SinkRig()
        try rig.open()
        try await rig.deliver(frames: 0..<12)
        #expect(rig.end(.user))
        #expect(rig.end(.interrupted))
        rig.queue.sync { rig.sink.storage(freeBytes: 0) }
        #expect(await rig.waitForFinishes())
        try await Task.sleep(for: .milliseconds(300))
        #expect(rig.finished.value == 1)
        let report = try #require(rig.takeReport())
        #expect(report.end == .user)
        #expect(report.facts.framesWritten == 12)
    }

    @Test func aClipThatHasNotEndedHasNoReport() async throws {
        let rig = try SinkRig()
        try rig.open()
        try await rig.deliver(frames: 0..<5)
        #expect(rig.takeReport() == nil)
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        #expect(rig.takeReport() != nil)
        // Taken once: the sink is idle again and a stop finds nothing in flight.
        #expect(rig.takeReport() == nil)
        #expect(!rig.end(.user))
    }

    @Test func aLowStorageReadingEndsTheClipAtItsLastFrame() async throws {
        let rig = try SinkRig()
        try rig.open(minFreeBytes: 1_000)
        try await rig.deliver(frames: 0..<9)
        rig.queue.sync { rig.sink.storage(freeBytes: 5_000) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(rig.finished.value == 0)
        rig.queue.sync { rig.sink.storage(freeBytes: 1_000) }
        #expect(await rig.waitForFinishes())
        let report = try #require(rig.takeReport())
        #expect(report.end == .storageFull)
        #expect(report.facts.framesWritten == 9)
        let facts = try await ClipInspector.inspect(url: rig.url, requestedFrameRate: 30)
        #expect(facts.frameCount == 9)
    }

    @Test func aTimedOutClipReportsTimedOutAndALateFinishIsIgnored() async throws {
        let rig = try SinkRig()
        try rig.open()
        try await rig.deliver(frames: 0..<6)
        #expect(rig.end(.user))
        let report = try #require(rig.takeReport(timedOut: true))
        #expect(report.end == .timedOut)
        #expect(report.facts.framesWritten == 6)
        // The file stays whatever the writer does next.
        _ = await rig.waitForFinishes(1)
        try await Task.sleep(for: .milliseconds(300))
        #expect(path.fileExists(atPath: rig.url.path(percentEncoded: false)))
    }

    @Test func soundIsWrittenOnceVideoHasStarted() async throws {
        let rig = try SinkRig()
        try rig.open(recordsSound: true)
        // Sound before the first frame is not written and is not a drop.
        try await rig.deliverSound(frames: 0..<1)
        try await rig.deliver(frames: 0..<30)
        try await rig.deliverSound(frames: 0..<30)
        #expect(rig.end(.user))
        #expect(await rig.waitForFinishes())
        let report = try #require(rig.takeReport())
        #expect(report.facts.total == 0)
        #expect(report.facts.audioBuffersNotWritten == 0)
        let facts = try await ClipInspector.inspect(url: rig.url, requestedFrameRate: 30)
        #expect(facts.hasAudio)
        #expect(facts.frameCount == 30)
    }
}
