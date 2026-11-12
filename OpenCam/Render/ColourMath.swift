import Foundation

/// The colour stage of an edit or look, applied to one Display P3-encoded colour.
/// Display P3 and sRGB share one transfer curve, so these formulas work on P3-encoded values unchanged.
nonisolated enum ColourMath {
    /// Encoded to linear, using the sRGB / Display P3 transfer curve.
    static func decode(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear to encoded, clamping to 0...1 first.
    static func encode(_ l: Float) -> Float {
        let x = clamp01(l)
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    /// Rec. 709 weights on P3-encoded values, a deliberate simplification.
    static func luma(_ rgb: SIMD3<Float>) -> Float {
        0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
    }

    /// Display P3-encoded in and out, 0...1. The stages, in this order:
    /// 1 linear light and exposure, 2 white balance, 3 encoded and contrast, 4 tones (highlights, shadows, whites, blacks),
    /// 5 point curves (the RGB curve, then the channel's own curve; skipped when every curve is identity),
    /// 6 vibrance, 7 saturation, 8 clamp.
    static func apply(_ adjustments: Adjustments, to rgb: SIMD3<Float>) -> SIMD3<Float> {
        func t(_ key: AdjustmentKey) -> Float { Float(adjustments[key]) / 100 }

        // 1: linear light, then exposure.
        var l = SIMD3(decode(rgb.x), decode(rgb.y), decode(rgb.z))
        l *= pow(2, Float(adjustments.exposure))

        // 2: white balance.
        l.x *= 1 + 0.3 * t(.temperature)
        l.y *= 1 - 0.3 * t(.tint)
        l.z *= 1 - 0.3 * t(.temperature)

        // 3: back to encoded, then contrast about mid grey.
        var x = SIMD3(encode(l.x), encode(l.y), encode(l.z))
        let contrast = 1 + t(.contrast)
        x = SIMD3(repeating: 0.5) + (x - SIMD3(repeating: 0.5)) * contrast
        x = clamp01(x)

        // 4: tones (highlights, shadows, whites, blacks), per channel.
        let highlights = t(.highlights), shadows = t(.shadows), whites = t(.whites), blacks = t(.blacks)
        func tone(_ v: Float) -> Float {
            var v = v
            v += highlights * v * v * (1 - v)
            v += shadows * v * (1 - v) * (1 - v)
            v = clamp01(v + 0.25 * whites * v * v)
            v = clamp01(v + 0.25 * blacks * (1 - v) * (1 - v))
            return v
        }
        x = SIMD3(tone(x.x), tone(x.y), tone(x.z))

        // 5: point curves. The RGB curve first, then each channel's own.
        let curves = adjustments.curves
        if !curves.isIdentity {
            func curved(_ v: Float, _ channel: CurveChannel) -> Float {
                curves[channel].value(at: curves.master.value(at: v))
            }
            x = SIMD3(curved(x.x, .red), curved(x.y, .green), curved(x.z, .blue))
        }

        // 6: vibrance leaves already saturated colours alone.
        let spread = x.max() - x.min()
        var y = luma(x)
        x = SIMD3(repeating: y) + (x - SIMD3(repeating: y)) * (1 + t(.vibrance) * (1 - spread))

        // 7: saturation.
        y = luma(x)
        x = SIMD3(repeating: y) + (x - SIMD3(repeating: y)) * (1 + t(.saturation))

        // 8: clamp.
        return clamp01(x)
    }

    private static func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }

    private static func clamp01(_ v: SIMD3<Float>) -> SIMD3<Float> {
        v.clamped(lowerBound: .zero, upperBound: .one)
    }
}
