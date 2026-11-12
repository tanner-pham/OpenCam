import Foundation

/// The capture outputs a configuration can have attached. The order of the cases is the order they are removed and added in.
nonisolated enum SessionOutput: Int, CaseIterable, Sendable {
    case photo, movie, writerVideo, writerSound
    /// The preview-sized data output that draws a look on the viewfinder.
    case lookFrames
}
