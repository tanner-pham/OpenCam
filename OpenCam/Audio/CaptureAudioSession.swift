import Foundation

/// The one thing the audio device needs from the capture session: whether the session sets up the app's audio session itself
/// (`AVCaptureSession.automaticallyConfiguresApplicationAudioSession`, which also picks the microphone to match the camera).
nonisolated protocol CaptureAudioSession: Sendable {
    func setConfiguresAudioSessionAutomatically(_ isAutomatic: Bool) async
}
