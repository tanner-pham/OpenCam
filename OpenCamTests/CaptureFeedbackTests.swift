import Foundation
import Testing
@testable import OpenCam

/// The counters the blink and the haptics follow: each changes once per event, and a refused press changes none.
@MainActor @Suite struct CaptureFeedbackTests {
    func deviceModel(_ fake: FakeSessionConfigurator, mode: CaptureMode = .video) throws -> CameraModel {
        let source = CapabilitySource(cacheDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                                      documentsDirectory: nil, discoverLenses: { [] }, scan: { _ in [] })
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: false, defaults: try Fixture.freshDefaults(),
                                capabilitySource: source, captureStore: try CaptureStore(directory: TestFiles.directory()))
        model.mode = mode
        model.phase = .ready
        model.attachSession(fake, configuredWith: try #require(model.sessionConfiguration), selection: model.currentSelection)
        return model
    }

    func removeClips(of fake: FakeSessionConfigurator) async {
        for url in await fake.recordingURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @Test func aPhotoRequestCountsOnceAndARefusedPressDoesNot() throws {
        let model = try deviceModel(FakeSessionConfigurator(failingLensIDs: []), mode: .photo)
        #expect(model.feedback == CaptureFeedback())
        model.capturePressed()
        #expect(model.feedback.photosTaken == 1)
        // Refused: the Library covers the camera, then the camera is not ready.
        model.isLibraryPresented = true
        model.capturePressed(); model.handleCaptureEvent(phase: .ended)
        model.isLibraryPresented = false
        model.phase = .scanning
        model.capturePressed()
        #expect(model.feedback == CaptureFeedback(photosTaken: 1, recordingsStarted: 0, recordingsStopped: 0))
    }

    @Test func aRecordingCountsItsStartAndItsStop() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        model.capturePressed()
        #expect(await eventually { model.recordingStart != nil })
        #expect(model.feedback.recordingsStarted == 1); #expect(model.feedback.recordingsStopped == 0)
        model.capturePressed()
        #expect(await eventually { !model.isRecording })
        #expect(model.feedback == CaptureFeedback(photosTaken: 0, recordingsStarted: 1, recordingsStopped: 1))
        // No space left: the press is refused and nothing counts.
        model.freeBytes = 0
        model.capturePressed()
        #expect(!model.isRecording); #expect(model.feedback.recordingsStarted == 1)
        await removeClips(of: fake)
    }

    /// Storage full ends the clip with no press; the stop still counts, once.
    @Test func aRecordingThatEndsByItselfStillCountsItsStop() async throws {
        let fake = FakeSessionConfigurator(failingLensIDs: [], isClipInFlight: true)
        let model = try deviceModel(fake)
        let option = try #require(model.currentVideoOption)
        model.capturePressed()
        #expect(await eventually { model.recordingStart != nil })
        let url = try #require(await fake.recordingURLs.first)
        model.recordingDidFinish(RecordingResult(url: url, option: option, outcome: .stopped(.storageFull, isPlayable: true), sidecar: nil))
        #expect(!model.isRecording)
        #expect(model.feedback == CaptureFeedback(photosTaken: 0, recordingsStarted: 1, recordingsStopped: 1))
        // A result that arrives again for the same clip counts nothing more.
        model.endRecordingWithoutResult(clip: url, context: "test")
        #expect(model.feedback.recordingsStopped == 1)
        await removeClips(of: fake)
    }

    @Test func quickPressesEachCount() async throws {
        let photoModel = try deviceModel(FakeSessionConfigurator(failingLensIDs: []), mode: .photo)
        photoModel.capturePressed(); photoModel.capturePressed(); photoModel.handleCaptureEvent(phase: .ended)
        #expect(photoModel.feedback.photosTaken == 3)

        let fake = FakeSessionConfigurator(failingLensIDs: [])
        let model = try deviceModel(fake)
        for round in 1...2 {
            model.capturePressed()
            #expect(await eventually { model.recordingStart != nil })
            model.capturePressed()
            #expect(await eventually { !model.isRecording })
            #expect(model.feedback.recordingsStarted == round); #expect(model.feedback.recordingsStopped == round)
        }
        await removeClips(of: fake)
    }
}
