import CoreMedia
import Foundation

/// Plain numbers and flags read off the camera and its active format in one actor turn, so every decision about a manual
/// setting (what its limits are, what it may call, how a value is clamped) is made in tested code and the device code only
/// reads and forwards.
nonisolated struct DeviceLimits: Sendable, Equatable {
    var minExposureDuration = CMTime.invalid
    var maxExposureDuration = CMTime.invalid
    /// `activeVideoMaxFrameDuration`; invalid in photo mode, where the default is in force.
    var frameDuration = CMTime.invalid
    var minISO: Float = 0
    var maxISO: Float = 0
    var minBias: Float = 0
    var maxBias: Float = 0
    /// `activeFormat.systemRecommendedExposureBiasRange`, when the format has one.
    var recommendedBias: ClosedRange<Float>?
    var maxWhiteBalanceGain: Float = 1
    /// True when the session has a video recorder's output attached (video mode): the movie output, or on the writer path its data output.
    var isVideo = false
    var isAutoFrameRateEnabled = false
    var supportsContinuousExposure = false
    var supportsCustomExposure = false
    var supportsContinuousWhiteBalance = false
    var supportsLockedWhiteBalance = false
    /// `isLockingWhiteBalanceWithCustomDeviceGainsSupported`.
    var supportsCustomGains = false
    var supportsContinuousFocus = false
    var supportsLockedFocus = false
    /// `isLockingFocusWithCustomLensPositionSupported`.
    var supportsCustomLensPosition = false
}
