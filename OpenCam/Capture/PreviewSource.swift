import AVFoundation

/// Hands the session to the preview layer on the main actor.
/// `AVCaptureSession` is not Sendable in the SDK; the preview layer only attaches to it and never configures it,
/// so this is the one unchecked crossing (Global Constraints).
nonisolated struct PreviewSource: @unchecked Sendable {
    let session: AVCaptureSession
}
