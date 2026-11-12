import CoreGraphics

/// Converts between a mask's picture coordinates (0...1 from the top left) and points on the picture as drawn.
nonisolated enum MaskGeometry {
    /// The picture coordinate under `location`, kept inside the picture.
    static func point(_ location: CGPoint, in size: CGSize) -> MaskPoint {
        guard size.width > 0, size.height > 0 else { return MaskPoint(x: 0, y: 0) }
        return MaskPoint(x: min(max(location.x / size.width, 0), 1), y: min(max(location.y / size.height, 0), 1))
    }

    static func location(_ point: MaskPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    /// The distance between two points as a fraction of the shorter side, as a radial mask stores its radius.
    static func radius(from centre: MaskPoint, to point: MaskPoint, in size: CGSize) -> Double {
        let short = min(size.width, size.height)
        guard short > 0 else { return 0 }
        return hypot((point.x - centre.x) * size.width, (point.y - centre.y) * size.height) / short
    }

    /// How far a radial mask's true radius is from the radius a touch measures, taken when a drag of its size handle starts.
    /// A circle larger than the picture has its handle held on the picture's edge, so the first touch measures less than the
    /// true radius; adding this offset to every later touch keeps the circle from shrinking to the edge.
    static func radiusGrabOffset(trueRadius: Double, centre: MaskPoint, touch: MaskPoint, in size: CGSize) -> Double {
        trueRadius - radius(from: centre, to: touch, in: size)
    }

    /// The radius for a size-handle drag at `touch`, keeping the offset taken at the start of the drag.
    static func radius(dragging touch: MaskPoint, from centre: MaskPoint, grabOffset: Double, in size: CGSize) -> Double {
        radius(from: centre, to: touch, in: size) + grabOffset
    }
}
