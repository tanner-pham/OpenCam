import AVFoundation

extension CameraSession: CaptureAudioSession {
    /// Runs on the session's queue. Off, the session leaves the app's audio session alone (AVCaptureSession.h), so a chosen
    /// microphone stays chosen; on, every start configures and activates it as before.
    func setConfiguresAudioSessionAutomatically(_ isAutomatic: Bool) {
        session.automaticallyConfiguresApplicationAudioSession = isAutomatic
    }
}
