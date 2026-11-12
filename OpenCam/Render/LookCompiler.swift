import Foundation

/// Evaluates the colour stage of adjustments on a lattice to produce a colour table.
nonisolated enum LookCompiler {
    static func cube(for adjustments: Adjustments) -> ColourCube {
        build(dimension: ColourCube.standardDimension) { ColourMath.apply(adjustments, to: $0) }
    }

    /// The identity table.
    static func lattice(dimension: Int) -> ColourCube {
        build(dimension: dimension) { $0 }
    }

    /// A table that applies `perChannel` to red, green and blue on their own.
    static func cube(dimension: Int = ColourCube.standardDimension, perChannel: (Float) -> Float) -> ColourCube {
        build(dimension: dimension) { SIMD3(perChannel($0.x), perChannel($0.y), perChannel($0.z)) }
    }

    private static func build(dimension: Int, transform: (SIMD3<Float>) -> SIMD3<Float>) -> ColourCube {
        let count = max(dimension, 0)
        let scale = Float(max(count - 1, 1))
        var data = [Float]()
        data.reserveCapacity(count * count * count * 4)
        for b in 0..<count {
            for g in 0..<count {
                for r in 0..<count {
                    let out = transform(SIMD3(Float(r) / scale, Float(g) / scale, Float(b) / scale))
                    data.append(contentsOf: [out.x, out.y, out.z, 1])
                }
            }
        }
        return ColourCube(dimension: count, data: data)
    }
}
