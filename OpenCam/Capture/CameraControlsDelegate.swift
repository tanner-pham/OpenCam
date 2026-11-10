import AVFoundation
import OSLog

/// "A controls delegate must be specified for controls to become active" (AVCaptureSession.h). The app draws no zoom
/// or exposure sliders of its own to hide during the full-screen appearance, so the callbacks only log.
nonisolated final class CameraControlsDelegate: NSObject, AVCaptureSessionControlsDelegate {
    private static let logger = Logger(subsystem: "local.opencam.app", category: "CameraControls")

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsDidBecomeActive] Controls active")
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsWillEnterFullscreenAppearance] Full-screen appearance begins")
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsWillExitFullscreenAppearance] Full-screen appearance ends")
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        Self.logger.debug("[CameraControlsDelegate:sessionControlsDidBecomeInactive] Controls inactive")
    }
}
