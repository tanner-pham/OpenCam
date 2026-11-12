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
}
