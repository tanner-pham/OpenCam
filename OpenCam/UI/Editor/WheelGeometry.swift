import CoreGraphics
import Foundation

/// Maps a grading wheel's square canvas, `diameter` on a side with the disc filling it, to a hue and saturation.
nonisolated enum WheelGeometry {
    static let maxDiameter: CGFloat = 160
    /// The grading panel's padding on each side.
    static let sideInset = Theme.Space.l
    /// Between the two lower wheels.
    static let columnGap = Theme.Space.m

    /// Two wheels side by side fill the panel up to `maxDiameter`: 160 pt in the folded portrait panel, 138 pt in the 320 pt one.
    static func diameter(forWidth width: CGFloat) -> CGFloat {
        max(0, min(maxDiameter, ((width - 2 * sideInset - columnGap) / 2).rounded(.down)))
    }

    /// Hue: the angle from the centre, 0 at the right, increasing clockwise on screen; saturation: distance / radius, capped at
    /// 100; both rounded to whole numbers; a saturation of 0 gives hue 0, so a puck at the centre is no edit. A hue that rounds
    /// to 360 is 0.
    static func tint(at point: CGPoint, diameter: CGFloat) -> (hue: Double, saturation: Double) {
        let radius = Double(diameter) / 2
        let dx = Double(point.x) - radius, dy = Double(point.y) - radius
        guard radius > 0, dx.isFinite, dy.isFinite else { return (0, 0) }
        let saturation = min(100, (hypot(dx, dy) / radius * 100).rounded())
        guard saturation > 0 else { return (0, 0) }
        let degrees = (atan2(dy, dx) * 180 / .pi).rounded()
        return ((degrees + 360).truncatingRemainder(dividingBy: 360), saturation)
    }

    /// What one VoiceOver swipe moves the wheel's sliders: 15° of hue, 5 of saturation.
    static let hueStep = 15.0
    static let saturationStep = 5.0

    /// `hue` moved by `steps` of `hueStep` degrees, wrapping 345 to 0 and 0 back to 345 (a hue of 360 is 0).
    static func steppedHue(_ hue: Double, steps: Int) -> Double {
        let moved = (hue + Double(steps) * hueStep).truncatingRemainder(dividingBy: 360)
        return moved < 0 ? moved + 360 : moved
    }

    /// `saturation` moved by `steps` of `saturationStep`, held to 0...100.
    static func steppedSaturation(_ saturation: Double, steps: Int) -> Double {
        min(100, max(0, saturation + Double(steps) * saturationStep))
    }

    /// Where the puck of this hue and saturation sits on the canvas: the inverse of `tint(at:diameter:)`.
    static func point(hue: Double, saturation: Double, diameter: CGFloat) -> CGPoint {
        let radius = Double(diameter) / 2
        let distance = radius * min(max(saturation, 0), 100) / 100
        return CGPoint(x: radius + distance * __cospi(hue / 180), y: radius + distance * __sinpi(hue / 180))
    }
}
