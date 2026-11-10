import Synchronization

/// Keeps the most recently built colour table, so slider moves that leave the colour adjustments unchanged reuse it.
/// Safe from any thread: the one entry is guarded by a `Mutex`; the table is built outside the lock.
nonisolated final class ColourCubeCache: Sendable {
    private let build: @Sendable (Adjustments) -> ColourCube
    private let last = Mutex<(key: Adjustments, cube: ColourCube)?>(nil)

    init(build: @escaping @Sendable (Adjustments) -> ColourCube = { LookCompiler.cube(for: $0) }) {
        self.build = build
    }

    func cube(for adjustments: Adjustments) -> ColourCube {
        let key = Self.colourPart(of: adjustments)
        if let cached = last.withLock({ $0?.key == key ? $0?.cube : nil }) { return cached }
        let cube = build(key)
        last.withLock { $0 = (key, cube) }
        return cube
    }

    /// Only the adjustments the table depends on: exposure through saturation.
    private static func colourPart(of adjustments: Adjustments) -> Adjustments {
        var colour = Adjustments()
        for key in AdjustmentKey.allCases.prefix(while: { $0 != .sharpening }) { colour[key] = adjustments[key] }
        return colour
    }
}
