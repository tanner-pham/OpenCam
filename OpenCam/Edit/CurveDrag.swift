import Foundation

/// One finger (or Pencil) on the curve editor, from touch-down: the curve it started on, with the point it holds. Every
/// update is worked out from `original`, so the curve never drifts from the finger, and a point dragged off and back is
/// restored.
nonisolated struct CurveDrag: Equatable, Sendable {
    /// The curve when the touch began, with the point it inserted when it began on the line.
    let original: ToneCurve
    /// The point being dragged in `original`.
    let index: Int

    /// Only `begin` makes a drag, so `index` is always a point of `original`.
    private init(original: ToneCurve, index: Int) {
        self.original = original
        self.index = index
    }

    /// `.point(i)` drags i; `.curve` inserts a point and drags it; `.none` is nil (nothing happens), as is a touch on the
    /// line where no point can be added.
    static func begin(on curve: ToneCurve, at location: CurvePoint, radius: Double) -> CurveDrag? {
        switch curve.hit(location, radius: radius) {
        case .point(let index): CurveDrag(original: curve, index: index)
        case .curve: curve.inserting(at: location.x).map { CurveDrag(original: $0.curve, index: $0.index) }
        case .none: nil
        }
    }

    /// True for the first and last points, which clamp at the plot's edge and are never removed.
    var isEnd: Bool { index == 0 || index == original.points.count - 1 }

    /// The curve while dragging by `translation` (normalised, y up). An inner point whose target is more than `margin`
    /// outside 0...1 on either axis is left out (removed on release); the ends clamp instead.
    func curve(translation: CurvePoint, margin: Double) -> ToneCurve {
        guard original.points.indices.contains(index) else { return original }
        let target = self.target(translation: translation)
        func isFarOutside(_ v: Double) -> Bool { v < -margin || v > 1 + margin }
        if !isEnd, isFarOutside(target.x) || isFarOutside(target.y) { return original.removing(index) }
        return original.moving(index, to: target)
    }

    /// Where the finger has taken the point, unclamped.
    func target(translation: CurvePoint) -> CurvePoint {
        let start = original.points.indices.contains(index) ? original.points[index] : CurvePoint(x: 0, y: 0)
        return CurvePoint(x: start.x + translation.x, y: start.y + translation.y)
    }
}
