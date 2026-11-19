import CoreMedia
import Foundation

/// The writer calls iOS 27 deprecates (add, start, an input's readiness and its append), behind one non-deprecated protocol so
/// the build has no warning, as `WriterAppending` does for the recorder. The only conformer is `SampleClipWriter`.
nonisolated protocol ClipFrameWriting: AnyObject {
    /// Opens the file and its session at time zero; the reason when it cannot.
    func begin() -> String?
    func isReady() -> Bool
    func append(_ frame: CMSampleBuffer) -> Bool
    /// The writer's own error text, if it has failed.
    func failure() -> String?
    /// Stops a writer that has begun and not finished; call on every failure after `begin()`.
    func cancel()
    /// Finishes the file; the reason when it could not be finished.
    func finish() async -> String?
}
