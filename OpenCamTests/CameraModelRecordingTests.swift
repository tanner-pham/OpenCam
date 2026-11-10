import Foundation
import Testing
@testable import OpenCam

@MainActor @Suite struct CameraModelRecordingTests {
    @Test func interruptionResetsUI() throws {
        let model = CameraModel(config: .parse(["app", "-recording", "on"]), capabilities: try Fixture.load(), isSimulator: true, defaults: try Fixture.freshDefaults())
        let option = try #require(model.currentVideoOption)
        model.recordingDidFinish(RecordingResult(url: URL(filePath: "/tmp/OC_0002.MOV"), option: option, outcome: .stopped(.interrupted, isPlayable: true), sidecar: nil))
        #expect(!model.isRecording && model.recordingStart == nil)
        #expect(model.notice == "Recording stopped. The camera was interrupted. Clip saved."); #expect(model.lastCapture?.lastPathComponent == "OC_0002.MOV")
    }
}
