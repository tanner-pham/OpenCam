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
