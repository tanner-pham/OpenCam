import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct CameraModelRecordingTests {
    @Test func recordSettingsAndTheSweepStayClosedWhileRecording() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        #expect(model.isRecording); #expect(!model.canOpenRecordSettings)
        model.openRecordSettings(); #expect(model.sheet == nil)
        model.openSweep(); #expect(model.sheet == nil)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0002.MOV"), option: option, outcome: .completed, sidecar: nil))
        #expect(model.canOpenRecordSettings)
        model.openSweep(); #expect(model.sheet == .sweep)
    }
    @Test func interruptionResetsUI() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0002.MOV"), option: option, outcome: .stopped(.interrupted, isPlayable: true), sidecar: nil))
        #expect(!model.isRecording && model.recordingStart == nil)
        #expect(model.notice == "Recording stopped. The camera was interrupted. Clip saved."); #expect(model.lastCapture?.lastPathComponent == "OC_0002.MOV")
    }
    @Test func interruptionEndingKeepsTheRecordingNotice() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        model.apply(.interrupted(.cameraInUse))
        #expect(model.notice == "Camera paused. Another app is using it.")
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0002.MOV"), option: option, outcome: .stopped(.interrupted, isPlayable: true), sidecar: nil))
        model.apply(.interruptionEnded)
        #expect(model.notice == "Recording stopped. The camera was interrupted. Clip saved.")
    }
    @Test func backgroundingKeepsTheRecordingNotice() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        model.apply(.interrupted(.background))
        #expect(model.notice == nil)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0002.MOV"), option: option, outcome: .stopped(.interrupted, isPlayable: true), sidecar: nil))
        model.apply(.interruptionEnded)
        #expect(model.notice == "Recording stopped. The camera was interrupted. Clip saved.")
    }
    @Test func mediaServicesRestartKeepsTheRecordingNotice() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        model.apply(.runtimeError("[CameraSession:runtimeError] Session stopped — {code: -11819}"))
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0002.MOV"), option: option, outcome: .stopped(.other(code: -11819), isPlayable: false), sidecar: nil))
        model.apply(.restarted)
        #expect(model.phase == .ready); #expect(model.notice == "Recording failed. The clip could not be saved.")
    }
    @Test func interruptionNoticeClearsWhenItEnds() throws {
        let model = CameraModel(config: LaunchConfig(), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        model.apply(.interrupted(.multipleForegroundApps))
        #expect(model.notice == "Camera paused while another app is on screen.")
        model.apply(.interruptionEnded)
        #expect(model.notice == nil)
    }
    @Test func interruptionDoesNotCoverACaptureNotice() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0002.MOV"), option: option, outcome: .stopped(.storageFull, isPlayable: true), sidecar: nil))
        model.apply(.interrupted(.cameraInUse)); model.apply(.interruptionEnded)
        #expect(model.notice == "Recording stopped. Storage is full. Clip saved.")
    }
    @Test func unknownFrameCountShowsNoDroppedFramesNotice() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        let facts = ClipFacts(codecFourCC: "hvc1", width: 3840, height: 2160, nominalFrameRate: 30, durationSeconds: 3, frameCount: nil,
                              droppedFrames: nil, colour: .rec709, megabitsPerSecond: 27, hasAudio: true)
        let sidecar = ClipSidecar(requested: option, actual: facts, outcome: "completed", recordedAt: Date(), error: nil)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0003.MOV"), option: option, outcome: .completed, sidecar: sidecar))
        #expect(model.notice == nil); #expect(model.lastCapture?.lastPathComponent == "OC_0003.MOV")
    }
}
