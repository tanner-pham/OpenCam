import CoreGraphics
import CoreImage
import ImageIO

/// How a camera frame is turned upright for the viewfinder. `CameraSession.apply` makes the data output's connection
/// neutral (angle 0, no mirroring) while configuring, so every buffer arrives in the sensor's own orientation, unmirrored,
/// and the pipeline does all turning and mirroring: it turns the image by the preview's angle, then flips it horizontally
/// for a front camera, which matches the preview layer's mirror.
nonisolated struct FrameOrientation: Sendable, Equatable {
    /// `.up`, or `.right`, `.down`, `.left` for 90, 180 and 270 degrees.
    var imageRotation: CGImagePropertyOrientation
    /// The image is flipped horizontally after it is turned; true for a front camera.
    var imageMirrors: Bool

    /// `angle` is the preview's horizon-level angle, taken to the nearest quarter turn.
    static func plan(angle: CGFloat, isFront: Bool) -> FrameOrientation {
        FrameOrientation(imageRotation: rotation(for: angle), imageMirrors: isFront)
    }

    /// Turns `image`, then mirrors it when the plan says so. The frame callback uses this for every frame.
    func apply(to image: CIImage) -> CIImage {
        let turned = image.oriented(imageRotation)
        return imageMirrors ? turned.oriented(.upMirrored) : turned
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
