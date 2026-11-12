import Synchronization

/// Keeps the most recently used colour tables (one by default), so slider moves that leave the colour adjustments unchanged reuse them.
/// Safe from any thread: the entries are guarded by a `Mutex`; a table is built outside the lock.
nonisolated final class ColourCubeCache: Sendable {
    private let build: @Sendable (Adjustments) -> ColourCube
    private let capacity: Int
    /// Least recently used first.
    private let entries = Mutex<[(key: Adjustments, cube: ColourCube)]>([])

    init(capacity: Int = 1, build: @escaping @Sendable (Adjustments) -> ColourCube = { LookCompiler.cube(for: $0) }) {
        self.capacity = max(1, capacity)
        self.build = build
    }

    func cube(for adjustments: Adjustments) -> ColourCube {
        let key = adjustments.colourPart
        let hit: ColourCube? = entries.withLock { entries in
            guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.cube
        }
        if let hit { return hit }
        let cube = build(key)
        entries.withLock { entries in
            entries.removeAll { $0.key == key }
            entries.append((key, cube))
            if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        }
        return cube
    }
}
