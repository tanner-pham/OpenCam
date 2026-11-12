import Foundation

/// Grows one brush stroke from touch samples. A dab's radius is `radius * (0.35 + 0.65 * pressure)`; no pressure (a finger) counts as full.
nonisolated struct BrushStrokeBuilder: Sendable {
    private let radius: Double
    private(set) var stroke: BrushStroke

    init(radius: Double, isErasing: Bool) {
        self.radius = radius
        stroke = BrushStroke(dabs: [], isErasing: isErasing)
    }

    /// Adds a dab at `point`. False, and nothing added, when it is closer than a quarter of its radius to the last dab.
    /// The distance is in picture fractions, like the points themselves.
    mutating func add(_ point: MaskPoint, pressure: Double?) -> Bool {
        let level = min(max(pressure ?? 1, 0), 1)
        let dabRadius = radius * (0.35 + 0.65 * level)
        if let last = stroke.dabs.last, hypot(point.x - last.x, point.y - last.y) < dabRadius / 4 { return false }
        stroke.dabs.append(BrushDab(x: point.x, y: point.y, radius: dabRadius))
        return true
    }
}
