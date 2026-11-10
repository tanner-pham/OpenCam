import Foundation

/// Decides when a look's frames have not arrived; the viewfinder then falls back to the plain preview.
nonisolated enum FrameWatch {
    static let timeout: Duration = .seconds(2)

    /// True when no frame arrived since the configure and the timeout has passed.
    static func isStalled(framesSinceConfigure: Int, elapsed: Duration) -> Bool {
        framesSinceConfigure == 0 && elapsed >= timeout
    }
}
