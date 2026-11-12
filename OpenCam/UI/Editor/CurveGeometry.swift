import CoreGraphics

/// Maps the curve editor's square canvas to curve units. The plot is inset by `inset` on every edge, so a point on the
/// border can still be touched and drawn whole; (0, 0) is the plot's bottom left.
nonisolated struct CurveGeometry: Equatable {
    static let inset: CGFloat = 12
    /// How far from a point (or the line) a touch still takes it.
    static let hitRadius: CGFloat = 22
    /// How far past the plot's edge an inner point is dragged before it is removed.
    static let removeMargin: CGFloat = 24

    /// The canvas is side x side.
    let side: CGFloat

    /// The plot's side, at least 1 pt, so a canvas of 24 pt or less never divides by zero.
    private var plot: CGFloat { max(side - 2 * Self.inset, 1) }

    func viewPoint(_ p: CurvePoint) -> CGPoint {
        CGPoint(x: Self.inset + CGFloat(p.x) * plot, y: Self.inset + CGFloat(1 - p.y) * plot)
    }

    /// Unclamped: a location off the plot maps outside 0...1.
    func curvePoint(_ v: CGPoint) -> CurvePoint {
        CurvePoint(x: Double((v.x - Self.inset) / plot), y: Double(1 - (v.y - Self.inset) / plot))
    }

    /// `hitRadius` in curve units.
    var hitRadius: Double { Double(Self.hitRadius / plot) }

    /// `removeMargin` in curve units.
    var removeMargin: Double { Double(Self.removeMargin / plot) }
}
