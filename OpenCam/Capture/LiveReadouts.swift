import Foundation

/// Values read from the camera for the readouts; nil when not available.
nonisolated struct LiveReadouts: Sendable, Equatable {
    var iso: Float?
    var shutterSeconds: Double?
    var kelvin: Float?
    var tint: Float?
    var exposureBias: Float?
    /// 0 (nearest) ... 1 (farthest), AVCaptureDevice.h `lensPosition`.
    var lensPosition: Float?
}
