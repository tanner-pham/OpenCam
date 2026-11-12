import Foundation

/// What the current camera and its active format allow. Nil or false: this camera cannot set that control.
nonisolated struct ManualRanges: Sendable, Equatable {
    /// In video the upper end is the frame time.
    var shutterSeconds: ClosedRange<Double>?
    var iso: ClosedRange<Float>?
    var bias: ClosedRange<Float>?
    var hasWhiteBalance = false
    var hasFocus = false
    /// Video only.
    var frameSeconds: Double?
}
