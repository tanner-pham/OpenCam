import Foundation

/// A 3D colour table in the order Core Image's colour cube filters read it.
nonisolated struct ColourCube: Sendable, Equatable {
    static let standardDimension = 33

    let dimension: Int
    /// RGBA, alpha 1. Red varies fastest, then green, then blue.
    let data: [Float]

    /// The Float bytes, for `CIColorCubeWithColorSpace.cubeData`.
    var cubeData: Data { data.withUnsafeBytes { Data($0) } }
}
