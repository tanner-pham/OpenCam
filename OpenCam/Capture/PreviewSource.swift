import AVFoundation

/// Hands the session to the preview layer on the main actor.
/// `AVCaptureSession` is not Sendable in the SDK; the preview layer only attaches to it and never configures it,
/// so this is the one unchecked crossing (Global Constraints).
nonisolated struct PreviewSource: @unchecked Sendable {
    /// Posted with the `AVCaptureSession` as object after each configure, so the preview can follow a camera change
    /// on a running session, which posts no start notification.
    static let didConfigureNotification = Notification.Name("local.opencam.app.PreviewSource.didConfigure")

    let session: AVCaptureSession
}
