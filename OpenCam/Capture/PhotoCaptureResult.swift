import Foundation

/// The files one request wrote, in the order they arrived, and the first error the capture reported, if any.
/// Both can be present: one file of a RAW + HEIF pair may save while the other fails.
nonisolated struct PhotoCaptureResult: Sendable, Equatable {
    let saved: [URL]
    let error: PhotoCaptureError?
}
