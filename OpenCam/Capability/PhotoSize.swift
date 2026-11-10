import Foundation

/// A maximum photo size a camera format can capture.
nonisolated struct PhotoSize: Sendable, Hashable {
    let width: Int
    let height: Int
}
