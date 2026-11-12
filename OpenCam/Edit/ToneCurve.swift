import Foundation

/// A tone curve through control points, evaluated as a monotone cubic Hermite spline (Fritsch–Butland tangents).
///
/// Points `(x_k, y_k)`, `k = 0…n`. Spacing `h_k = x_{k+1} − x_k`, secants `d_k = (y_{k+1} − y_k) / h_k`.
/// Tangents: `m_0 = d_0`, `m_n = d_{n−1}`; inside, `m_k = 0` when `d_{k−1}·d_k ≤ 0`, else
/// `m_k = (w_1 + w_2) / (w_1/d_{k−1} + w_2/d_k)` with `w_1 = 2h_k + h_{k−1}` and `w_2 = h_k + 2h_{k−1}`.
/// On the segment holding `x`, with `t = (x − x_k) / h_k`:
/// `y = (2t³−3t²+1)·y_k + (t³−2t²+t)·h_k·m_k + (−2t³+3t²)·y_{k+1} + (t³−t²)·h_k·m_{k+1}`.
/// Flat outside the end points; the result is clamped to 0...1. The curve never overshoots the y values of the points
/// on either side of the segment, whatever the spacing. Only the two tangents of the segment being evaluated are computed.
nonisolated struct ToneCurve: Codable, Sendable, Hashable {
    static let maxPoints = 16
    static let minGap = 0.01
    static let identity = ToneCurve(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)])

    let points: [CurvePoint]
    /// Set with the points: stage 5 of `ColourMath.apply` asks once per lattice point of every table it builds. Not coded.
    let isIdentity: Bool

    private enum CodingKeys: String, CodingKey { case points }

    /// Normalises: each coordinate snapped by `snapped(_:)`; sorted by x; a point closer than `minGap` in x to the one kept
    /// before it is dropped; above `maxPoints` the first 15 and the last are kept; fewer than 2 left is `identity`. The first
    /// and the last point are never dropped for being close to an inner one.
    init(points: [CurvePoint]) {
        let thousandths = Self.thousandths
        let minGapThousandths = thousandths(Self.minGap)
        let sorted = points.map { CurvePoint(x: Self.snapped($0.x), y: Self.snapped($0.y)) }.sorted { $0.x < $1.x }
        guard let first = sorted.first, let last = sorted.last, sorted.count >= 2,
              thousandths(last.x) - thousandths(first.x) >= minGapThousandths else {
            self.points = Self.identityPoints
            self.isIdentity = true
            return
        }
        var kept = [first]
        for point in sorted.dropFirst().dropLast() {
            guard let before = kept.last else { continue }
            if thousandths(point.x) - thousandths(before.x) >= minGapThousandths,
               thousandths(last.x) - thousandths(point.x) >= minGapThousandths { kept.append(point) }
        }
        kept.append(last)
        if kept.count > Self.maxPoints { kept = Array(kept.prefix(Self.maxPoints - 1)) + [last] }
        self.points = kept
        self.isIdentity = kept == Self.identityPoints
    }

    /// A coordinate clamped to 0...1 and snapped to the nearest thousandth; one that is not finite is 0.
    static func snapped(_ v: Double) -> Double { Double(thousandths(v)) / 1000 }

    /// A coordinate clamped to 0...1, in whole thousandths; one that is not finite (a drag over a canvas with no size) is 0
    /// rather than a trap. Gaps are compared in these, so 0.21 after 0.2 is a gap of exactly 10 (as Doubles, 0.21 − 0.2 is
    /// less than 0.01).
    static func thousandths(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return Int((min(max(v, 0), 1) * 1000).rounded())
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(points: try container.decode([CurvePoint].self, forKey: .points))
    }

    private static let identityPoints = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    func value(at x: Float) -> Float {
        guard let first = points.first, let last = points.last else { return x }
        if x <= Float(first.x) { return Float(first.y) }
        if x >= Float(last.x) { return Float(last.y) }
        var k = 0
        while k < points.count - 2, x >= Float(points[k + 1].x) { k += 1 }
        let x0 = Float(points[k].x), x1 = Float(points[k + 1].x), y0 = Float(points[k].y), y1 = Float(points[k + 1].y)
        let h = x1 - x0, t = (x - x0) / h
        let m0 = tangent(at: k), m1 = tangent(at: k + 1)
        let t2 = t * t, t3 = t2 * t
        let y = (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m1
        return min(max(y, 0), 1)
    }

    private func spacing(_ k: Int) -> Float { Float(points[k + 1].x - points[k].x) }
    private func secant(_ k: Int) -> Float { Float(points[k + 1].y - points[k].y) / spacing(k) }

    /// The Fritsch–Butland tangent at point `k`.
    private func tangent(at k: Int) -> Float {
        if k == 0 { return secant(0) }
        if k == points.count - 1 { return secant(k - 1) }
        let before = secant(k - 1), after = secant(k)
        if before * after <= 0 { return 0 }
        let w1 = 2 * spacing(k) + spacing(k - 1), w2 = spacing(k) + 2 * spacing(k - 1)
        return (w1 + w2) / (w1 / before + w2 / after)
    }
}
