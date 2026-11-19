import CoreGraphics
import Foundation

/// Turns a touch in the viewfinder into a point on the sensor: the inverse of `FrameOrientation`. The shown picture is the
/// sensor's image turned by `rotation` (taken to the nearest quarter turn), mirrored for a front camera, aspect-fit and centred
/// in the view as `FrameFit` places it.
nonisolated struct PreviewGeometry: Sendable, Equatable {
    let viewSize: CGSize
    let sensorSize: CGSize
    /// Degrees, any value; the preview connection's `videoRotationAngle`.
    let rotation: Double
    let isMirrored: Bool

    /// The Simulator: the picture is the view, upright and not mirrored.
    static func filling(_ size: CGSize) -> PreviewGeometry {
        PreviewGeometry(viewSize: size, sensorSize: size, rotation: 0, isMirrored: false)
    }

    /// Nil outside the aspect-fit picture, or with an empty size.
    func devicePoint(forViewPoint point: CGPoint) -> FocusPoint? {
        guard let picture = pictureRect, point.x.isFinite, point.y.isFinite else { return nil }
        let slack = 1e-9
        var u = (point.x - picture.minX) / picture.width
        var v = (point.y - picture.minY) / picture.height
        guard (-slack...(1 + slack)).contains(u), (-slack...(1 + slack)).contains(v) else { return nil }
        u = min(max(u, 0), 1)
        v = min(max(v, 0), 1)
        if isMirrored { u = 1 - u }
        switch quarterTurns {
        case 1: return FocusPoint(x: v, y: 1 - u)
        case 2: return FocusPoint(x: 1 - u, y: 1 - v)
        case 3: return FocusPoint(x: 1 - v, y: u)
        default: return FocusPoint(x: u, y: v)
        }
    }

    /// Where `point` is drawn in the view: the inverse of `devicePoint(forViewPoint:)`. The origin for an empty size.
    func viewPoint(for point: FocusPoint) -> CGPoint {
        guard let picture = pictureRect else { return .zero }
        var u: Double
        let v: Double
        switch quarterTurns {
        case 1: (u, v) = (1 - point.y, point.x)
        case 2: (u, v) = (1 - point.x, 1 - point.y)
        case 3: (u, v) = (point.y, 1 - point.x)
        default: (u, v) = (point.x, point.y)
        }
        if isMirrored { u = 1 - u }
        return CGPoint(x: picture.minX + u * picture.width, y: picture.minY + v * picture.height)
    }

    private var quarterTurns: Int {
        guard rotation.isFinite else { return 0 }
        let turns = (rotation / 90).rounded().truncatingRemainder(dividingBy: 4)
        return (Int(turns) + 4) % 4
    }

    /// The shown picture, in view coordinates; nil when any size is empty.
    private var pictureRect: CGRect? {
        guard viewSize.width > 0, viewSize.height > 0, sensorSize.width > 0, sensorSize.height > 0 else { return nil }
        let shown = quarterTurns % 2 == 1 ? CGSize(width: sensorSize.height, height: sensorSize.width) : sensorSize
        let scale = min(viewSize.width / shown.width, viewSize.height / shown.height)
        let size = CGSize(width: shown.width * scale, height: shown.height * scale)
        return CGRect(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2, width: size.width, height: size.height)
    }
}
