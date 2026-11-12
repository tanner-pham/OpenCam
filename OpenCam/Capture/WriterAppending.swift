import CoreMedia
import Foundation

/// The writer calls iOS 27 deprecates (an input's readiness and its append). The sink's witnesses are marked deprecated and
/// everything else reaches them through this protocol, so the build has no warning and the deprecated calls stay in one place.
/// Call inside the writer queue.
nonisolated protocol WriterAppending {
    func isVideoReady() -> Bool
    func isAudioReady() -> Bool
    func appendVideo(_ sampleBuffer: CMSampleBuffer) -> Bool
    func appendAudio(_ sampleBuffer: CMSampleBuffer) -> Bool
}
