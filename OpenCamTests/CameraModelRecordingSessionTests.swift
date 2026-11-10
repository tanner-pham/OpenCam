import Foundation
import Testing
@testable import OpenCam

/// The model's recording path against a fake session: starting, stopping, and a result that never arrives.
@MainActor @Suite struct CameraModelRecordingSessionTests {
    func deviceModel(_ fake: FakeSessionConfigurator) throws -> CameraModel {
        let source = CapabilitySource(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                                      documentsDirectory: nil, discoverLenses: { [] }, scan: { _ in [] })
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source)
        model.phase = .ready
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return model
    }

    func removeClips(of fake: FakeSessionConfigurator) async {
        for url in await fake.recordingURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func aStopWithNoClipInFlightEndsTheRecording() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        model.capturePressed()
        #expect(model.isRecording); #expect(!model.canChangeLensOrMode)
        #expect(await eventually { model.recordingStart != nil })
        model.capturePressed()
        #expect(await eventually { !model.isRecording })
        #expect(model.recordingStart == nil); #expect(model.notice == RecordingOutcome.failedNotice)
        #expect(model.canChangeLensOrMode); #expect(model.canOpenRecordSettings)
        #expect(await fake.stopRecordingCount == 1)
        await removeClips(of: fake)
    }

    @Test func aStopWithNoResultNeverCallsAFileOnDiskLost() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [], onStartRecording: { url, _ in
            FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data())
        })
        let model = try deviceModel(fake)
        model.capturePressed()
        #expect(await eventually { model.recordingStart != nil })
        model.capturePressed()
        #expect(await eventually { !model.isRecording })
        #expect(model.notice == RecordingOutcome.incompleteNotice); #expect(model.notice != RecordingOutcome.failedNotice)
        await removeClips(of: fake)
    }

    @Test func aStopWithAClipInFlightWaitsForItsResult() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [], isClipInFlight: true)
        let model = try deviceModel(fake)
        model.capturePressed()
        #expect(await eventually { model.recordingStart != nil })
        model.capturePressed()
        let wasStopped = await eventually { model.isRecording == false }
        #expect(!wasStopped); #expect(await fake.stopRecordingCount == 1); #expect(model.isRecording)
        await removeClips(of: fake)
    }

    @Test func aRestartWhileRecordingEndsTheRecording() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [], isClipInFlight: true)
        let model = try deviceModel(fake)
        model.capturePressed()
        #expect(await eventually { model.recordingStart != nil })
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11819}"))
        model.apply(.restarted)
        #expect(!model.isRecording); #expect(model.recordingStart == nil); #expect(model.phase == .ready)
        #expect(model.notice == RecordingOutcome.failedNotice); #expect(model.canChangeLensOrMode)
        await removeClips(of: fake)
    }

    @Test func aRestartClearsAScriptedRecording() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults())
        #expect(model.isRecording)
        model.apply(.restarted)
        #expect(!model.isRecording); #expect(model.recordingStart == nil)
    }

    /// The model drives a real sweep; the first clip is interrupted as it starts, while a capture notice is on screen.
    func sweepInterruptedAtTheFirstClip(by reason: InterruptionReason) async throws {
        let sink = ResultSink()
        let fake = FakeSessionConfigurator(failingLensIDs: [], onStartRecording: { _, _ in await sink.send(.interrupted(reason)) })
        let model = try deviceModel(fake)
        sink.model = model
        let option = try #require(model.currentVideoOption)
        let facts = ClipFacts(codecFourCC: "hvc1", width: 3840, height: 2160, nominalFrameRate: 30, durationSeconds: 3, frameCount: 85,
                              droppedFrames: 5, colour: .rec709, megabitsPerSecond: 27, hasAudio: true)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0001.MOV"), option: option, outcome: .completed,
                                                 sidecar: ClipSidecar(requested: option, actual: facts, outcome: "completed", recordedAt: Date(), error: nil)))
        #expect(model.notice == "OC_0001 dropped 5 frames."); #expect(model.isCameraUsable)

        let options = Array(model.sweepOptions.prefix(3))
        try #require(options.count == 3)
        let store = try CaptureStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let lens = try #require(model.currentLens)
        let sweep = FormatSweep(driver: model, store: store, lens: lens, options: options, keepsClips: false, clipDuration: .milliseconds(10),
                                deadlines: SweepDeadlines(start: .seconds(2), finish: .seconds(2), cancelGrace: .milliseconds(10)))
        await model.runSweep(sweep, lensID: lens.id)

        #expect(model.isInterrupted); #expect(!model.isCameraUsable)
        #expect(sweep.rows.count == 1); #expect(sweep.rows.allSatisfy { !$0.hasAnswer })
        let name = try #require(sweep.reportURL?.lastPathComponent)
        #expect(sweep.resultText == "Stopped after 1 of 3. The camera stopped responding. Saved \(name).")
        #expect(model.failedCombinations.failedByLens[lens.id] == nil)
        #expect(!model.isSweeping); #expect(!model.isRecording)
        await removeClips(of: fake)
    }

    @Test func aPhoneCallDuringASweepEndsItWhileACaptureNoticeShows() async throws {
        try await sweepInterruptedAtTheFirstClip(by: .cameraInUse)
    }

    @Test func backgroundingDuringASweepEndsIt() async throws {
        try await sweepInterruptedAtTheFirstClip(by: .background)
    }

    @Test func aClipThatEndsAsItStartsLeavesNoStartTime() async throws {
        let sink = ResultSink()
        let fake = FakeSessionConfigurator(failingLensIDs: [], onStartRecording: { url, option in await sink.finishAtOnce(url: url, option: option) })
        let model = try deviceModel(fake)
        sink.model = model
        model.capturePressed()
        #expect(await eventually { !model.isRecording })
        // Let the start resume after its await.
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.recordingStart == nil); #expect(!model.isRecording)
        await removeClips(of: fake)
    }
}
