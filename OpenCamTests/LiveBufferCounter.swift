import Foundation
import Synchronization

/// Counts `Data` buffers made by `data(copying:)` that are still alive, so a test can see when one is released.
final class LiveBufferCounter: Sendable {
    private let alive = Mutex(0)

    var count: Int { alive.withLock { $0 } }

    /// A copy of `bytes` whose storage, once freed, lowers the count.
    func data(copying bytes: Data) -> Data {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: max(bytes.count, 1), alignment: 1)
        bytes.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: bytes.count)
        alive.withLock { $0 += 1 }
        return Data(bytesNoCopy: pointer, count: bytes.count, deallocator: .custom { [self] pointer, _ in
            pointer.deallocate()
            alive.withLock { $0 -= 1 }
        })
    }
}
