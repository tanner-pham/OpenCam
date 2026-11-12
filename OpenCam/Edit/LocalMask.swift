import Foundation

/// A point in the picture, 0...1 from the top left.
nonisolated struct MaskPoint: Codable, Sendable, Hashable {
    var x: Double
    var y: Double
}

/// One touch of a brush. The radius is a fraction of the picture's shorter side.
nonisolated struct BrushDab: Codable, Sendable, Hashable {
    var x: Double
    var y: Double
    var radius: Double
}

/// One drag of the brush, painting or erasing.
nonisolated struct BrushStroke: Codable, Sendable, Hashable {
    var dabs: [BrushDab]
    var isErasing = false
}

nonisolated enum MaskKind: String, CaseIterable, Sendable {
    case linear, radial, brush, subject

    var title: String {
        switch self {
        case .linear: "Linear"
        case .radial: "Radial"
        case .brush: "Brush"
        case .subject: "Subject"
        }
    }

    var defaultShape: MaskShape {
        switch self {
        case .linear: .linear(start: MaskPoint(x: 0.5, y: 0), end: MaskPoint(x: 0.5, y: 0.5))
        case .radial: .radial(centre: MaskPoint(x: 0.5, y: 0.5), radius: 0.3, feather: 0.5)
        case .brush: .brush(strokes: [])
        case .subject: .subject
        }
    }
}

/// Where a mask applies. Geometry is stored as given and clamped once, when rendering.
nonisolated enum MaskShape: Codable, Sendable, Hashable {
    /// Full effect at `start`, none at `end`.
    case linear(start: MaskPoint, end: MaskPoint)
    /// Radius is a fraction of the shorter side: full effect inside `radius * (1 - feather)`, none beyond `radius`.
    case radial(centre: MaskPoint, radius: Double, feather: Double)
    case brush(strokes: [BrushStroke])
    case subject

    var kind: MaskKind {
        switch self {
        case .linear: .linear
        case .radial: .radial
        case .brush: .brush
        case .subject: .subject
        }
    }
}

/// A region of the picture with its own adjustments.
nonisolated struct LocalMask: Codable, Sendable, Hashable, Identifiable {
    /// The adjustments a mask can carry.
    static let keys: [AdjustmentKey] = [.exposure, .contrast, .highlights, .shadows, .temperature, .tint, .saturation]

    var id = UUID()
    var shape: MaskShape
    var isInverted = false
    var adjustments = Adjustments()
}
