import AVFoundation
import OSLog

/// "A controls delegate must be specified for controls to become active" (AVCaptureSession.h). When the controls enter
/// their full-screen appearance, "applications are encouraged to hide portions of their user interface including zoom or
/// exposure sliders" (AVCaptureSession.h), so that callback tells the model to close the open manual slider; the others
/// only log.
nonisolated final class CameraControlsDelegate: NSObject, AVCaptureSessionControlsDelegate {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "CameraControls")
    private let events: AsyncStream<SessionEvent>.Continuation

    init(events: AsyncStream<SessionEvent>.Continuation) {
        self.events = events
    }

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsDidBecomeActive] Controls active")
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsWillEnterFullscreenAppearance] Full-screen appearance begins")
        events.yield(.systemControlsFullscreen)
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsWillExitFullscreenAppearance] Full-screen appearance ends")
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsDidBecomeInactive] Controls inactive")
    }
}
