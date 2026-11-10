import CoreGraphics

nonisolated enum ThumbnailState: Sendable {
    case loading, ready(CGImage), failed
}
