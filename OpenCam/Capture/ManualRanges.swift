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
