import Foundation
@testable import OpenCam

/// Lets a fake session deliver a recording result to a model created after the fake.
@MainActor final class ResultSink {
    weak var model: CameraModel?

    /// Sends the session event to the model, as the session's event stream would.
    func send(_ event: SessionEvent) {
        model?.apply(event)
    }

    /// A clip that ended as it started, with an unplayable file.
    func finishAtOnce(url: URL, option: VideoOption) {
        model?.recordingDidFinish(RecordingResult(url: url, option: option, outcome: .stopped(.other(code: -11800), isPlayable: false), sidecar: nil))
    }
}
