import Foundation

/// The edits the curve editor makes, all in normalised units (x and y 0...1). Every result is a normalised `ToneCurve`.
nonisolated extension ToneCurve {
    /// The nearest point within `radius`; else `.curve` when |value(at: x) − y| ≤ radius and x is between the end points;
    /// else `.none`.
    func hit(_ location: CurvePoint, radius: Double) -> CurveHit {
        var nearest: (index: Int, distance: Double)?
        for (index, point) in points.enumerated() {
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance <= radius, distance < nearest?.distance ?? .infinity { nearest = (index, distance) }
        }
        if let nearest { return .point(nearest.index) }
        guard let first = points.first, let last = points.last, location.x >= first.x, location.x <= last.x else { return .none }
        return abs(Double(value(at: Float(location.x))) - location.y) <= radius ? .curve : .none
    }

    /// A point at (x, value(at: x)), so the picture does not change; nil at `maxPoints`, within `minGap` of a point, or
    /// outside the ends.
    func inserting(at x: Double) -> (curve: ToneCurve, index: Int)? {
        guard points.count < Self.maxPoints, x.isFinite, let first = points.first, let last = points.last else { return nil }
        let at = Self.thousandths(x), gap = Self.thousandths(Self.minGap)
        guard at - Self.thousandths(first.x) >= gap, Self.thousandths(last.x) - at >= gap,
              !points.contains(where: { abs(Self.thousandths($0.x) - at) < gap }) else { return nil }
        let snappedX = Double(at) / 1000
        let curve = ToneCurve(points: points + [CurvePoint(x: snappedX, y: Double(value(at: Float(snappedX))))])
        guard curve.points.count == points.count + 1,
              let index = curve.points.firstIndex(where: { Self.thousandths($0.x) == at }) else { return nil }
        return (curve, index)
    }

    /// x kept at least `minGap` from its neighbours (the first point 0...next − minGap, the last previous + minGap...1),
    /// compared in whole thousandths; y 0...1; both snapped.
    func moving(_ index: Int, to location: CurvePoint) -> ToneCurve {
        guard points.indices.contains(index) else { return self }
        let gap = Self.thousandths(Self.minGap)
        let lower = index > 0 ? Self.thousandths(points[index - 1].x) + gap : 0
        let upper = index < points.count - 1 ? Self.thousandths(points[index + 1].x) - gap : 1000
        guard lower <= upper else { return self }
        var moved = points
        moved[index] = CurvePoint(x: Double(min(max(Self.thousandths(location.x), lower), upper)) / 1000, y: Self.snapped(location.y))
        return ToneCurve(points: moved)
    }

    /// The first and last points are never removed: returns self.
    func removing(_ index: Int) -> ToneCurve {
        guard index > 0, index < points.count - 1 else { return self }
        var kept = points
        kept.remove(at: index)
        return ToneCurve(points: kept)
    }
}
