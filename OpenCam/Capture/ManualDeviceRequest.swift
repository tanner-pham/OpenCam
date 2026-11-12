import CoreMedia
import Foundation

/// Exactly what the session passes to the device for one `ManualApplyPlan`, decided from plain numbers: the plan's values clamped
/// once more against the limits read off the device, "the camera's current value" where a number is missing, and no action at
/// all where the device lacks the mode or lock. The device code reads the limits, asks for this, and forwards each field that is
/// present; it does no arithmetic and makes no decision of its own.
nonisolated struct ManualDeviceRequest: Sendable, Equatable {
    enum Exposure: Sendable, Equatable {
        case continuous
        /// Nil: the camera's current duration or ISO.
        case custom(duration: CMTime?, iso: Float?)
    }

    enum WhiteBalance: Sendable, Equatable {
        case continuous
        /// Leave the device locked: automatic was asked for during a RAW clip.
        case stayLocked
        /// The device converts the kelvin and tint to gains; the result goes through `clampedGains` with `maxGain`.
        case locked(kelvin: Float, tint: Float, maxGain: Float)
    }

    /// What happens to the mode a RAW clip will restore.
    enum Restore: Sendable, Equatable {
        case leave
        /// Nothing is restored: white balance was set by hand during the clip.
        case clear
        /// Continuous white balance is restored when the clip ends.
        case toContinuous
    }

    enum Focus: Sendable, Equatable {
        case continuous
        case locked(Float)
    }

    struct Gains: Sendable, Equatable {
        var red: Float
        var green: Float
        var blue: Float
    }

    /// A value the device's limits moved; logged, not thrown.
    struct Clamp: Sendable, Equatable {
        var control: String
        var asked: Double
        var set: Double
    }

    /// `activeVideoMaxFrameDuration = .invalid`.
    var resetsFrameDuration = false
    var exposure: Exposure?
    var bias: Float?
    var whiteBalance: WhiteBalance?
    var restore = Restore.leave
    var focus: Focus?
    var clamps: [Clamp] = []

    /// What the device did, for the settings the session reports.
    struct Outcome: Sendable, Equatable {
        var didSetExposure: Bool
        /// The white balance actually set when a gain was clamped.
        var whiteBalance: ManualSettings.WhiteBalance?
    }

    static func make(_ plan: ManualApplyPlan, limits: DeviceLimits) -> ManualDeviceRequest {
        var request = ManualDeviceRequest()
        if let exposure = plan.exposure {
            // Setting the frame duration throws while auto video frame rate is on (AVCaptureDevice.h).
            request.resetsFrameDuration = plan.restoresFrameDuration && !limits.isAutoFrameRateEnabled
            switch exposure {
            case .continuous:
                if limits.supportsContinuousExposure { request.exposure = .continuous }
            case .custom(let seconds, let iso):
                if limits.supportsCustomExposure { request.setCustomExposure(seconds: seconds, iso: iso, limits: limits) }
            }
        }
        if let bias = plan.bias, bias.isFinite {
            let value = ManualApplyPlan.clampedValue(bias, lower: limits.minBias, upper: limits.maxBias)
            request.bias = value
            request.note("bias", asked: Double(bias), set: Double(value))
        }
        if let whiteBalance = plan.whiteBalance {
            switch whiteBalance {
            case .continuous:
                if limits.supportsContinuousWhiteBalance { request.whiteBalance = .continuous }
            case .continuousAfterClip:
                if limits.supportsContinuousWhiteBalance {
                    request.whiteBalance = .stayLocked
                    request.restore = .toContinuous
                }
            case .locked(let kelvin, let tint):
                if limits.supportsCustomGains, limits.supportsLockedWhiteBalance, kelvin.isFinite, tint.isFinite {
                    request.whiteBalance = .locked(kelvin: kelvin, tint: tint, maxGain: limits.maxWhiteBalanceGain)
                    request.restore = .clear
                }
            }
        }
        if let focus = plan.focus {
            switch focus {
            case .continuous:
                if limits.supportsContinuousFocus { request.focus = .continuous }
            case .locked(let position):
                if limits.supportsLockedFocus, limits.supportsCustomLensPosition, position.isFinite {
                    let value = ManualApplyPlan.clampedValue(position, lower: 0, upper: 1)
                    request.focus = .locked(value)
                    request.note("focus", asked: Double(position), set: Double(value))
                }
            }
        }
        return request
    }

    /// The automatic state a configure or a restart returns the camera to: continuous exposure, bias 0 (only when the device's
    /// limits bracket it), continuous white balance and continuous autofocus, each only where supported.
    static func resetting(_ limits: DeviceLimits) -> ManualDeviceRequest {
        var request = ManualDeviceRequest()
        if limits.supportsContinuousExposure { request.exposure = .continuous }
        if limits.minBias <= 0, limits.maxBias >= 0 { request.bias = 0 }
        if limits.supportsContinuousWhiteBalance { request.whiteBalance = .continuous }
        if limits.supportsContinuousFocus { request.focus = .continuous }
        return request
    }

    /// The settings the camera has after `plan` ran: the plan's, except an exposure that was not set stays what it was, and a
    /// white balance the device clamped is the one it reports.
    static func result(of plan: ManualApplyPlan, previous: ManualSettings?, outcome: Outcome) -> ManualSettings {
        var result = plan.applied
        if plan.exposure != nil, !outcome.didSetExposure { result.exposure = previous?.exposure ?? .automatic }
        if let whiteBalance = outcome.whiteBalance { result.whiteBalance = whiteBalance }
        return result
    }

    /// Each gain between 1 and `max` (non-finite gives 1), and whether any was moved. The device's own conversion of kelvin and
    /// tint to gains can return any value, and only gains inside 1...`maxWhiteBalanceGain` may reach the setter or the
    /// conversion back (AVCaptureDevice.h).
    static func clampedGains(_ gains: Gains, max: Float) -> (gains: Gains, wasClamped: Bool) {
        let clamped = Gains(red: ManualApplyPlan.clampedGain(gains.red, max: max),
                            green: ManualApplyPlan.clampedGain(gains.green, max: max),
                            blue: ManualApplyPlan.clampedGain(gains.blue, max: max))
        return (clamped, clamped != gains)
    }

    private mutating func setCustomExposure(seconds: Double?, iso: Float?, limits: DeviceLimits) {
        // In video the longest shutter is the frame time, or the clip's frame rate would drop (AVCaptureDevice.h, `:430`).
        var longest = limits.maxExposureDuration
        if limits.isVideo, limits.frameDuration.isNumeric, longest.isNumeric { longest = min(longest, limits.frameDuration) }
        var duration: CMTime?
        if let seconds, seconds.isFinite {
            duration = ManualApplyPlan.clampedDuration(seconds, minimum: limits.minExposureDuration, maximum: longest)
            // Logged only when the clamp moved the CMTime itself.
            if let duration, duration != CMTime(seconds: seconds, preferredTimescale: 1_000_000_000) {
                note("shutter", asked: seconds, set: duration.seconds)
            }
        }
        var sensitivity: Float?
        if let iso, iso.isFinite {
            let value = ManualApplyPlan.clampedValue(iso, lower: limits.minISO, upper: limits.maxISO)
            sensitivity = value
            note("iso", asked: Double(iso), set: Double(value))
        }
        exposure = .custom(duration: duration, iso: sensitivity)
    }

    private mutating func note(_ control: String, asked: Double, set: Double) {
        if asked != set { clamps.append(Clamp(control: control, asked: asked, set: set)) }
    }
}
