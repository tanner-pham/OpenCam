import CoreGraphics
import ImageIO

/// How a camera frame is turned upright for the viewfinder. The data output's connection is never rotated: rotating it
/// physically rotates buffers and needs a lengthy capture pipeline reconfiguration (AVCaptureSession.h, `videoRotationAngle`),
/// and ProRes RAW buffers cannot be rotated at all. So the pipeline always turns the image by the preview's angle.
nonisolated struct FrameOrientation: Sendable, Equatable {
    /// `isVideoMirrored` on the data output's connection, set inside `CameraSession.apply` (with
    /// `automaticallyAdjustsVideoMirroring = false` first).
    var connectionMirrors: Bool
    /// Always applied by the pipeline: `.up`, or `.right`, `.down`, `.left` for 90, 180 and 270 degrees.
    var imageRotation: CGImagePropertyOrientation
    /// The pipeline flips the image horizontally after rotating it.
    var imageMirrors: Bool

    /// Front cameras are mirrored, back cameras never; the mirror goes on the connection when it supports one, else to the
    /// image. `angle` is the preview's horizon-level angle, taken to the nearest quarter turn.
    static func plan(angle: CGFloat, isFront: Bool, connectionCanMirror: Bool) -> FrameOrientation {
        FrameOrientation(connectionMirrors: isFront && connectionCanMirror,
                         imageRotation: rotation(for: angle),
                         imageMirrors: isFront && !connectionCanMirror)
    }

    private static func rotation(for angle: CGFloat) -> CGImagePropertyOrientation {
        guard angle.isFinite else { return .up }
        let quarterTurns = Int((angle / 90).rounded()) % 4
        switch (quarterTurns + 4) % 4 {
        case 1: return .right
        case 2: return .down
        case 3: return .left
        default: return .up
        }
    }
}
