import Foundation

/// The pinch's rules, with no camera in them. A pinch is a factor on the lens's own zoom (1 means no pinch), so it never leaves
/// the lens: on the combined back camera the lens is a zoom the camera is locked to, and the pinch only scales it.
nonisolated enum PinchZoom {
    /// The most a pinch zooms the lens in.
    static let cap = 10.0
    /// `ramp(toVideoZoomFactor:withRate:)` scales by pow(2, rate × seconds): about 9 ms per 5 percent step at 8.
    static let rampRate: Float = 8

    /// start × magnification in 1...cap; a non-finite or non-positive magnification keeps start.
    static func factor(from start: Double, magnification: Double) -> Double {
        guard magnification.isFinite, magnification > 0 else { return start }
        return min(max(start * magnification, 1), cap)
    }

    /// base × pinch, clamped to base...base × cap and to formatMax (never below base: a formatMax below base gives base).
    static func target(base: Double, pinch: Double, formatMax: Double) -> Double {
        let wanted = base * min(max(pinch, 1), cap)
        return max(base, min(wanted, formatMax))
    }

    /// The zoom a camera can hold for `target` when its available range is `availableMin...availableMax`: the target stopped at the
    /// range's top, or nil when the target lies below the range (a lens lock's range still moving: nothing is changed then).
    static func held(target: Double, availableMin: Double, availableMax: Double) -> Double? {
        target < availableMin ? nil : min(target, availableMax)
    }

    /// The strip's text: the lens's own factor (0.5 ultra wide, `zoomFactor` for wide, 1 for the front cameras) × pinch, to one
    /// decimal with ".0" dropped and "x" after; nil when that rounds to the lens's own text.
    static func label(for lens: Lens, pinch: Double) -> String? {
        let own = ownFactor(of: lens)
        let text = text(own * pinch)
        return text == Self.text(own) ? nil : text
    }

    /// True when `next` keeps the pinch: `previous` exists and lens id, mode, video and photo options are equal. A look, sound,
    /// recorder or combined-camera difference keeps it; a lens, mode or format change resets it.
    static func keeps(from previous: SessionConfiguration?, to next: SessionConfiguration) -> Bool {
        guard let previous else { return false }
        return previous.lens.id == next.lens.id && previous.mode == next.mode && previous.video == next.video
            && previous.photo == next.photo
    }

    private static func ownFactor(of lens: Lens) -> Double {
        switch lens.kind {
        case .ultraWide: 0.5
        case .wide: lens.zoomFactor
        case .outerUltraWide, .innerUltraWide: 1
        }
    }

    private static func text(_ factor: Double) -> String {
        let one = String(format: "%.1f", factor)
        return (one.hasSuffix(".0") ? String(one.dropLast(2)) : one) + "x"
    }
}
