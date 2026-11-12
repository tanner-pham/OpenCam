import CoreMedia
import Foundation

/// What one apply sets, decided from plain numbers before any device call, because a value outside the device's limits
/// raises an exception Swift cannot catch (AVCaptureDevice.h: `setExposureModeCustom`, `setExposureTargetBias`,
/// `setWhiteBalanceModeLocked` and `setFocusModeLocked` all throw NSRangeException).
nonisolated struct ManualApplyPlan: Sendable, Equatable {
    enum Exposure: Sendable, Equatable {
        case continuous
        /// Nil holds the value the camera has now.
        case custom(seconds: Double?, iso: Float?)
    }

    enum WhiteBalance: Sendable, Equatable {
        case continuous
        /// Automatic was asked for during a RAW clip, which records with white balance locked: the device stays locked
        /// and returns to continuous when the clip ends.
        case continuousAfterClip
        case locked(kelvin: Float, tint: Float)
    }

    enum Focus: Sendable, Equatable {
        case continuous
        case locked(Float)
    }

    /// Nil: leave as it is.
    var exposure: Exposure?
    var bias: Float?
    var whiteBalance: WhiteBalance?
    var focus: Focus?
    /// Photo mode only, with the exposure group changed: the frame rate the device lengthened for a long exposure returns to
    /// the format's default (`activeVideoMaxFrameDuration` as `.invalid`, AVCaptureDevice.h).
    var restoresFrameDuration = false
    /// The clamped settings the camera has once this plan has run.
    var applied: ManualSettings

    /// Every number is clamped here, so the device only repeats the clamp against its own limits. A control the camera lacks
    /// throws before anything is set; automatic needs nothing from the camera.
    static func make(_ settings: ManualSettings, applied: ManualSettings?, limits: ManualRanges, lens: String,
                     isRAWClipRecording: Bool) throws(ManualControlError) -> ManualApplyPlan {
        if settings.exposure != .automatic, limits.shutterSeconds == nil || limits.iso == nil {
            throw .notSupported(control: "exposure", lens: lens)
        }
        if settings.bias != nil, limits.bias == nil { throw .notSupported(control: "bias", lens: lens) }
        if settings.whiteBalance != .automatic, !limits.hasWhiteBalance { throw .notSupported(control: "white balance", lens: lens) }
        if settings.focus != nil, !limits.hasFocus { throw .notSupported(control: "focus", lens: lens) }

        let clamped = limits.clamped(settings)
        let changed = clamped.changedGroups(from: applied)
        var plan = ManualApplyPlan(applied: clamped)

        if changed.contains(.exposure) {
            switch clamped.exposure {
            case .automatic: plan.exposure = .continuous
            case .manual(let shutter, let iso): plan.exposure = .custom(seconds: shutter, iso: iso)
            }
            plan.restoresFrameDuration = !limits.isVideo
        }
        // Bias only steers metering while exposure is manual, so it waits: the plan remembers the bias the device has, and
        // the change is seen again when exposure returns to automatic.
        if clamped.exposure == .automatic {
            if changed.contains(.bias), let bias = clamped.bias { plan.bias = bias }
        } else {
            plan.applied.bias = applied?.bias
        }
        if changed.contains(.whiteBalance) {
            switch clamped.whiteBalance {
            case .automatic: plan.whiteBalance = isRAWClipRecording ? .continuousAfterClip : .continuous
            case .manual(let kelvin, let tint): plan.whiteBalance = .locked(kelvin: kelvin, tint: tint)
            }
        }
        if changed.contains(.focus) {
            plan.focus = clamped.focus.map { .locked($0) } ?? .continuous
        }
        return plan
    }

    /// 1...`max`; a non-finite gain is 1, and so is a maximum below 1 or not finite.
    static func clampedGain(_ gain: Float, max: Float) -> Float {
        let upper = max.isFinite && max >= 1 ? max : 1
        guard !gain.isNaN else { return 1 }
        return Swift.min(Swift.max(gain, 1), upper)
    }

    /// `seconds` as a `CMTime` clamped on `CMTime` values against the format's own limits, so the result is never a tick outside
    /// them (a comparison in seconds as doubles can land there). Nil when `seconds` or a limit cannot be used.
    static func clampedDuration(_ seconds: Double, minimum: CMTime, maximum: CMTime) -> CMTime? {
        guard seconds.isFinite, minimum.isNumeric, maximum.isNumeric else { return nil }
        let lower = minimum > maximum ? maximum : minimum
        let value = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
        guard value.isNumeric else { return nil }
        if value > maximum { return maximum }
        if value < lower { return lower }
        return value
    }

    /// `value` between `lower` and `upper` (a reversed pair is read in order); a non-finite value is the lower end.
    static func clampedValue(_ value: Float, lower: Float, upper: Float) -> Float {
        let low = Swift.min(lower, upper), high = Swift.max(lower, upper)
        guard low.isFinite, high.isFinite else { return low.isFinite ? low : 0 }
        guard value.isFinite else { return low }
        return Swift.min(Swift.max(value, low), high)
    }
}
