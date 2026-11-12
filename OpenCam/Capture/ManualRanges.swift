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
    /// True when the session has the movie output attached (video mode), false in photo mode. Never inferred from
    /// `frameSeconds`, which is also nil on a video format whose frame time cannot be read.
    var isVideo = false
}

extension ManualRanges {
    /// What the camera allows by hand, from what was read off it. Shutter and ISO need custom exposure and usable limits; in
    /// video the shutter's upper end is the frame time, and `isVideo` is stated, never inferred from the frame time.
    nonisolated static func make(from limits: DeviceLimits) -> ManualRanges {
        var ranges = ManualRanges()
        ranges.isVideo = limits.isVideo
        if limits.isVideo, limits.frameDuration.isNumeric, limits.frameDuration.seconds > 0 {
            ranges.frameSeconds = limits.frameDuration.seconds
        }
        let shortest = limits.minExposureDuration, longest = limits.maxExposureDuration
        if limits.supportsCustomExposure, shortest.isNumeric, longest.isNumeric, shortest.seconds > 0,
           limits.minISO.isFinite, limits.maxISO.isFinite, limits.minISO <= limits.maxISO {
            var upper = longest.seconds
            if let frame = ranges.frameSeconds { upper = min(upper, frame) }
            ranges.shutterSeconds = shortest.seconds...max(shortest.seconds, upper)
            ranges.iso = limits.minISO...limits.maxISO
        }
        // A recommended range with an infinite end is as good as none: the device's own limits stand in for it.
        if let recommended = limits.recommendedBias, recommended.lowerBound.isFinite, recommended.upperBound.isFinite {
            ranges.bias = recommended
        } else if limits.minBias.isFinite, limits.maxBias.isFinite, limits.minBias <= limits.maxBias {
            ranges.bias = limits.minBias...limits.maxBias
        }
        ranges.hasWhiteBalance = limits.supportsCustomGains && limits.supportsLockedWhiteBalance
            && limits.maxWhiteBalanceGain.isFinite && limits.maxWhiteBalanceGain >= 1
        ranges.hasFocus = limits.supportsLockedFocus && limits.supportsCustomLensPosition
        return ranges
    }

    /// Every number inside what this camera allows, and a group it lacks returned to automatic.
    /// A non-finite exposure number holds the camera's value; any other non-finite value is dropped.
    nonisolated func clamped(_ settings: ManualSettings) -> ManualSettings {
        var next = ManualSettings()
        if case .manual(let shutter, let iso) = settings.exposure, let shutterRange = shutterSeconds, let isoRange = self.iso {
            var upper = shutterRange.upperBound
            if let frameSeconds, frameSeconds.isFinite, frameSeconds > 0 { upper = min(upper, frameSeconds) }
            let low = shutterRange.lowerBound
            let high = max(low, upper)
            next.exposure = .manual(
                shutterSeconds: shutter.flatMap { $0.isFinite ? min(max($0, low), high) : nil },
                iso: iso.flatMap { $0.isFinite ? min(max($0, isoRange.lowerBound), isoRange.upperBound) : nil }
            )
        }
        if let value = settings.bias, value.isFinite, let range = bias {
            next.bias = min(max(value, range.lowerBound), range.upperBound)
        }
        if case .manual(let kelvin, let tint) = settings.whiteBalance, hasWhiteBalance, kelvin.isFinite, tint.isFinite {
            next.whiteBalance = .manual(kelvin: min(max(kelvin, 2500), 10000), tint: min(max(tint, -150), 150))
        }
        if let value = settings.focus, value.isFinite, hasFocus {
            next.focus = min(max(value, 0), 1)
        }
        return next
    }
}
