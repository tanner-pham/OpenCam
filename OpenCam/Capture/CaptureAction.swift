import AVKit

/// What a capture press does: the on-screen button and the Camera Control act the same way.
nonisolated enum CaptureAction: Equatable, Sendable {
    case takePhoto, startRecording, stopRecording

    /// A press of the on-screen button.
    static func forPress(mode: CaptureMode, isRecording: Bool) -> CaptureAction {
        switch mode {
        case .photo: .takePhoto
        case .video: isRecording ? .stopRecording : .startRecording
        }
    }

    /// Only a press that ends acts, as in the AVCaptureEventInteraction.h sample; began and cancelled do nothing.
    static func forEvent(phase: AVCaptureEventPhase, mode: CaptureMode, isRecording: Bool) -> CaptureAction? {
        guard phase == .ended else { return nil }
        return forPress(mode: mode, isRecording: isRecording)
    }
}
