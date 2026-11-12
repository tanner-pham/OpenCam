import AVFoundation
import Observation

/// What the second check's screen shows: the preview of the current trial's session and the progress line.
@Observable
final class RecorderCheck2Progress {
    var line = ""
    var isFinished = false
    @ObservationIgnored let previewView = RecorderCheck2PreviewUIView()

    func show(_ session: AVCaptureSession?) {
        previewView.show(session)
    }

    /// Whether the preview layer says it is rendering frames now.
    var isPreviewing: Bool? { previewView.previewLayer?.isPreviewing }
}
