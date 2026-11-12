import Foundation

/// Readout text; a missing value reads "--".
nonisolated enum ReadoutFormatter {
    static let missing = "--"

    /// Under 0.35 s as a fraction ("1/60"), otherwise seconds to at most one decimal ("0.4s", "1s", "2.5s"): a fraction rounded
    /// that far up would read as a different time ("1/3" for 1/2.5 s).
    static func shutter(_ s: Double?) -> String {
        guard let s, s.isFinite, s > 0 else { return missing }
        if s < 0.35 { return "1/\(Int((1 / s).rounded()))" }
        let tenths = Int((s * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)s" : "\(tenths / 10).\(tenths % 10)s"
    }

    static func iso(_ v: Float?) -> String {
        guard let v, v.isFinite else { return missing }
        return String(Int(v.rounded()))
    }

    /// To the nearest 50 K.
    static func kelvin(_ v: Float?) -> String {
        guard let v, v.isFinite else { return missing }
        return "\(Int((v / 50).rounded()) * 50)K"
    }

    /// Whole steps, signed: "+4", "-2", "0".
    static func tint(_ v: Float?) -> String {
        guard let v, v.isFinite else { return missing }
        let steps = Int(v.rounded())
        return steps > 0 ? "+\(steps)" : String(steps)
    }

    /// Exposure bias in EV to one decimal, signed: "+0.3", "-0.7", "0.0".
    static func bias(_ v: Float?) -> String {
        guard let v, v.isFinite else { return missing }
        let tenths = Int((v * 10).rounded())
        if tenths == 0 { return "0.0" }
        let sign = tenths > 0 ? "+" : "-"
        return "\(sign)\(abs(tenths) / 10).\(abs(tenths) % 10)"
    }

    /// Lens position 0...1 with two decimals.
    static func focus(_ v: Float?) -> String {
        guard let v, v.isFinite else { return missing }
        let hundredths = Int((min(max(v, 0), 1) * 100).rounded())
        return "\(hundredths / 100).\(String(format: "%02d", hundredths % 100))"
    }
}
