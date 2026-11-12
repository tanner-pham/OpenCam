import CoreMedia
import Foundation

/// Why a frame is missing from the file.
nonisolated enum DropReason: String, Codable, Sendable, CaseIterable {
    /// The output's drop callback (CMSampleBuffer.h:1762, :1773, :1784).
    case late, outOfBuffers, discontinuity
    /// Delivered, but the writer input was not ready for it.
    case writerNotReady
    /// Delivered more than one frame behind real time; not rendered, not written.
    case behind
    /// The Log render or its buffer pool failed.
    case renderFailed
    case other

    /// `value` is the `kCMSampleBufferAttachmentKey_DroppedFrameReason` attachment; nil or an unknown string is `.other`.
    init(attachment value: String?) {
        let late = kCMSampleBufferDroppedFrameReason_FrameWasLate as String
        let outOfBuffers = kCMSampleBufferDroppedFrameReason_OutOfBuffers as String
        let discontinuity = kCMSampleBufferDroppedFrameReason_Discontinuity as String
        switch value {
        case late: self = .late
        case outOfBuffers: self = .outOfBuffers
        case discontinuity: self = .discontinuity
        default: self = .other
        }
    }
}
