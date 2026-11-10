import Foundation
import Testing
@testable import OpenCam

/// Which adjustments belong to the colour table is said per key, never by the order of `allCases`.
@Suite struct ColourKeyTests {
    static let colourKeys: Set<AdjustmentKey> = [.exposure, .contrast, .highlights, .shadows, .whites, .blacks, .temperature, .tint,
                                                 .vibrance, .saturation]

    /// A value inside the range that is not zero: half the way to the upper bound.
    static func moved(_ key: AdjustmentKey) -> Adjustments {
        Adjustments().setting(key, to: key.range.upperBound / 2)
    }

    @Test func everyKeyIsClassifiedAndTheColourKeysAreExactlyTheOnesTheCompilerReads() {
        #expect(Set(AdjustmentKey.allCases.filter(\.isColour)) == Self.colourKeys)
        let samples: [SIMD3<Float>] = [SIMD3(0.1, 0.1, 0.1), SIMD3(0.5, 0.5, 0.5), SIMD3(0.9, 0.9, 0.9), SIMD3(0.8, 0.3, 0.2), SIMD3(0.2, 0.4, 0.7)]
        for key in AdjustmentKey.allCases {
            let adjustments = Self.moved(key)
            let isRead = samples.contains { ColourMath.apply(adjustments, to: $0) != ColourMath.apply(Adjustments(), to: $0) }
            #expect(isRead == key.isColour, "\(key) is read by the colour stage: \(isRead)")
            #expect(adjustments.hasColourChanges == key.isColour, "\(key)")
        }
    }

    /// The cached table is rebuilt for a change to a colour key, and kept for any other key.
    @Test func theTableCacheKeysOnTheColourKeysOnly() {
        for key in AdjustmentKey.allCases {
            let builds = CallCounter()
            let cache = ColourCubeCache { builds.increment(); return LookCompiler.cube(for: $0) }
            _ = cache.cube(for: Adjustments())
            _ = cache.cube(for: Self.moved(key))
            #expect(builds.value == (key.isColour ? 2 : 1), "\(key)")
        }
    }
}
