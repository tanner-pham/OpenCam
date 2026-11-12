import Foundation

extension CameraModel {
    /// True while the camera records sound or could: video mode on a running, uninterrupted camera.
    var isAudioLive: Bool {
        AudioState.isLive(phase: phase, mode: mode, isInterrupted: isInterrupted)
    }

    /// Shows the Audio section's notice; nil clears it. It never replaces a capture or configuration notice.
    func showAudioNotice(_ text: String?) {
        guard let text else {
            clearNotice(from: .audio)
            return
        }
        guard noticeSource != .capture, noticeSource != .configuration else { return }
        show(text, from: .audio)
    }
}
