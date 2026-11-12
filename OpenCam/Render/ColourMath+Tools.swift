import Foundation

/// The maths of the colour mixer and colour grading, on Display P3-encoded values.
nonisolated extension ColourMath {
    /// Degrees of hue a full mixer hue slider moves a colour.
    static let mixHueReach: Float = 30
    /// How far a full mixer luminance slider scales the value of a fully saturated colour.
    static let mixLuminanceReach: Float = 0.5
    /// How far a fully saturated grading tint pushes a colour.
    static let gradingStrength: Float = 0.25
    /// How far a full grading luminance slider lifts or drops a colour.
    static let gradingLuminanceReach: Float = 0.2
    /// How far the balance slider moves the shadow/highlight pivot from 0.5.
    static let balanceReach: Float = 0.25

    /// RGB to (hue, saturation, value): hue in 0..<360 degrees, saturation and value in 0...1.
    ///
    /// `V = max`, `C = max - min`, `S = C / V` (0 when `V == 0`).
    /// `H = 60 * ((g - b) / C mod 6)` when red is the maximum, `60 * ((b - r) / C + 2)` when green is,
    /// `60 * ((r - g) / C + 4)` when blue is, and 0 when `C == 0` (grey).
    static func hsv(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let maximum = max(rgb.x, rgb.y, rgb.z)
        let chroma = maximum - min(rgb.x, rgb.y, rgb.z)
        let saturation: Float = maximum == 0 ? 0 : chroma / maximum
        guard chroma > 0 else { return SIMD3(0, saturation, maximum) }
        let hue: Float
        if maximum == rgb.x {
            var sector = ((rgb.y - rgb.z) / chroma).truncatingRemainder(dividingBy: 6)
            if sector < 0 { sector += 6 }
            hue = 60 * sector
        } else if maximum == rgb.y {
            hue = 60 * ((rgb.z - rgb.x) / chroma + 2)
        } else {
            hue = 60 * ((rgb.x - rgb.y) / chroma + 4)
        }
        return SIMD3(hue >= 360 ? 0 : hue, saturation, maximum)
    }

    /// (hue, saturation, value) to RGB, the inverse of `hsv`. Hue wraps into 0..<360.
    ///
    /// `C = V * S`, `X = C * (1 - |(H / 60) mod 2 - 1|)`, `m = V - C`; the six sectors of `H / 60` place
    /// `C`, `X` and 0 on the channels, then `m` is added to each.
    static func rgb(hue: Float, saturation: Float, value: Float) -> SIMD3<Float> {
        var wrapped = hue.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        let sector = wrapped / 60
        let chroma = value * saturation
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let offset = value - chroma
        let base: SIMD3<Float>
        switch Int(sector) {
        case 0: base = SIMD3(chroma, second, 0)
        case 1: base = SIMD3(second, chroma, 0)
        case 2: base = SIMD3(0, chroma, second)
        case 3: base = SIMD3(0, second, chroma)
        case 4: base = SIMD3(second, 0, chroma)
        default: base = SIMD3(chroma, 0, second)
        }
        return base + SIMD3(repeating: offset)
    }

    /// How much each mixer band owns a hue (0..<360), in `ColourBand.allCases` order. The weights sum to 1
    /// and at most two are non-zero.
    ///
    /// Linear tents between neighbouring centres, with `c_8 = 360` wrapping back to red: for `H` in
    /// `[c_i, c_{i+1})`, `t = (H - c_i) / (c_{i+1} - c_i)`, `w_i = 1 - t`, `w_{(i+1) mod 8} = t`.
    static func bandWeights(hue: Float) -> SIMD8<Float> {
        var weights = SIMD8<Float>(repeating: 0)
        for index in 0..<8 {
            let lower = bandCentres[index]
            let upper: Float = index == 7 ? 360 : bandCentres[index + 1]
            guard hue >= lower, hue < upper else { continue }
            let t = (hue - lower) / (upper - lower)
            weights[index] = 1 - t
            weights[(index + 1) % 8] = t
            break
        }
        return weights
    }

    /// `ColourBand.centre` of each band in order, as a table the per-colour maths reads without a call.
    private static let bandCentres = SIMD8<Float>(0, 30, 60, 120, 180, 240, 270, 300)

    /// The colour mixer: moves hue, saturation and luminance of colours by the bands they sit in.
    ///
    /// `(H, S, V) = hsv(x)`, `w = bandWeights(H)`.
    /// `H' = (H + mixHueReach * sum(w * hue)) mod 360`, `S' = clamp01(S * (1 + sum(w * saturation)))`,
    /// `V' = clamp01(V * (1 + mixLuminanceReach * S * sum(w * luminance)))`; the result is `rgb(H', S', V')`.
    /// A grey is returned unchanged.
    static func mix(_ rgb: SIMD3<Float>, hue: SIMD8<Float>, saturation: SIMD8<Float>, luminance: SIMD8<Float>) -> SIMD3<Float> {
        let colour = hsv(rgb)
        guard colour.y > 0 else { return rgb }
        let weights = bandWeights(hue: colour.x)
        let shiftedHue = colour.x + mixHueReach * (weights * hue).sum()
        let newSaturation = clamp01(colour.y * (1 + (weights * saturation).sum()))
        let newValue = clamp01(colour.z * (1 + mixLuminanceReach * colour.y * (weights * luminance).sum()))
        return Self.rgb(hue: shiftedHue, saturation: newSaturation, value: newValue)
    }

    /// How much each grading region owns a colour of this luma: (shadows, midtones, highlights), summing to 1.
    ///
    /// Pivot `p = gradingPivot(balance)`, exponent `k = gradingExponent(blending)`.
    /// `w_s = clamp01(1 - Y / p)^k`, `w_h = clamp01((Y - p) / (1 - p))^k`, `w_m = 1 - w_s - w_h`.
    static func regionWeights(luma: Float, balance: Float, blending: Float) -> SIMD3<Float> {
        regionWeights(luma: luma, pivot: gradingPivot(balance: balance), exponent: gradingExponent(blending: blending))
    }

    /// `regionWeights(luma:balance:blending:)` with the pivot and exponent already worked out, as `GradingLanes` holds them.
    static func regionWeights(luma: Float, pivot: Float, exponent: Float) -> SIMD3<Float> {
        let shadows = pow(clamp01(1 - luma / pivot), exponent)
        let highlights = pow(clamp01((luma - pivot) / (1 - pivot)), exponent)
        return SIMD3(shadows, 1 - shadows - highlights, highlights)
    }

    /// The luma that splits shadows from highlights: `0.5 + balanceReach * balance`, for a balance of -1...1.
    static func gradingPivot(balance: Float) -> Float { 0.5 + balanceReach * balance }

    /// The power of the region weights: `2 * 2^(-blending)` (2 at 0, 1 at +1, 4 at -1), for a blending of -1...1.
    static func gradingExponent(blending: Float) -> Float { 2 * pow(2, -blending) }

    /// What a region tinted `hue` (degrees) at `saturation` (0...1) adds to a colour at full weight:
    /// `gradingStrength * saturation * o`, where `c = rgb(hue, 1, 1)` and `o = c - luma(c)` (a tint that keeps luma).
    static func gradingPush(hue: Float, saturation: Float) -> SIMD3<Float> {
        let colour = rgb(hue: hue, saturation: 1, value: 1)
        return gradingStrength * saturation * (colour - SIMD3(repeating: luma(colour)))
    }

    /// Colour grading: tints shadows, midtones and highlights separately.
    ///
    /// `Y = luma(x)`, weights from `regionWeights`. For each region `c = rgb(hue, 1, 1)` and `o = c - luma(c)`
    /// (a tint that keeps luma). Then
    /// `x' = clamp01(x + gradingStrength * sum(w_r * saturation_r * o_r) + gradingLuminanceReach * sum(w_r * luminance_r))`.
    /// Works through `grade(_:lanes:)`, so the maths is written once.
    static func grade(_ rgb: SIMD3<Float>, shadows: ColourTint, midtones: ColourTint, highlights: ColourTint,
                      balance: Float, blending: Float) -> SIMD3<Float> {
        grade(rgb, lanes: GradingLanes(shadows: shadows, midtones: midtones, highlights: highlights, balance: balance, blending: blending))
    }

    /// Colour grading of one colour, with each region's push and lift and the weights' pivot and exponent read from `lanes`
    /// rather than worked out again: the colour table calls this at every lattice point.
    static func grade(_ rgb: SIMD3<Float>, lanes: GradingLanes) -> SIMD3<Float> {
        let weights = regionWeights(luma: luma(rgb), pivot: lanes.pivot, exponent: lanes.exponent)
        let push = weights.x * lanes.shadowsPush + weights.y * lanes.midtonesPush + weights.z * lanes.highlightsPush
        return clamp01(rgb + push + (weights * lanes.lift).sum())
    }
}
