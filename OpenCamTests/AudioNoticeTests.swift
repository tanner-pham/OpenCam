import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct AudioNoticeTests {
    func model() throws -> CameraModel {
        CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults(),
                    captureStore: try CaptureStore(directory: TestFiles.directory()))
    }

    @Test func anAudioNoticeNeverCoversACaptureNotice() throws {
        let model = try model()
        model.showAudioNotice("Monitoring could not start.")
        #expect(model.notice == "Monitoring could not start."); #expect(model.noticeSource == .audio)
        // A newer capture result replaces it, and then no audio notice covers that one.
        model.show("Recording failed.", from: .capture)
        model.showAudioNotice("Microphone disconnected. Source is Automatic.")
        #expect(model.notice == "Recording failed."); #expect(model.noticeSource == .capture)
        model.clearNotice(from: .capture)
        model.show("Could not apply.", from: .configuration)
        model.showAudioNotice("Monitoring could not start.")
        #expect(model.notice == "Could not apply."); #expect(model.noticeSource == .configuration)
        // A newer audio notice does replace an older one.
        model.clearNotice(from: .configuration)
        model.showAudioNotice("one"); model.showAudioNotice("two")
        #expect(model.notice == "two")
    }

    @Test func clearingRemovesOnlyTheAudioNotice() throws {
        let model = try model()
        model.showAudioNotice("Monitoring could not start.")
        model.showAudioNotice(nil)
        #expect(model.notice == nil); #expect(model.noticeSource == nil)
        model.show("Recording failed.", from: .capture)
        model.showAudioNotice(nil)
        #expect(model.notice == "Recording failed."); #expect(model.noticeSource == .capture)
    }

    @Test func audioIsLiveOnlyInVideoOnARunningCamera() throws {
        let model = try model()
        #expect(model.isAudioLive == (model.mode == .video && (model.phase == .ready || model.phase == .simulator) && !model.isInterrupted))
        model.mode = .photo
        #expect(!model.isAudioLive)
    }
}
